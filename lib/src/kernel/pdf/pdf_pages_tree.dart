import 'pdf_document.dart';
import 'pdf_name.dart';
import 'pdf_pages.dart';
import 'pdf_page.dart';
import 'pdf_catalog.dart';
import 'pdf_dictionary.dart';
import 'pdf_array.dart';
import 'pdf_object.dart';
import '../exceptions/pdf_exception.dart';
import '../exceptions/kernel_exception_message_constant.dart';

/// Algorithm for construction of PdfPages tree.
/// Follows the same logic as  C# PdfPagesTree.
class PdfPagesTree {
  static const int defaultLeafSize = 10;

  final List<PdfIndirectReference?> _pageRefs = [];
  final List<PdfPage?> _pages = [];
  final List<PdfPages> _parents = [];
  PdfPages? _root;
  final PdfCatalog _catalog;
  PdfDocument? _document;
  bool _generated = false;

  PdfPagesTree(this._catalog);

  /// Sets the document reference
  void setDocument(PdfDocument doc) {
    _document = doc;
  }

  /// Initializes the pages tree by reading the tree structure from the catalog.
  /// Follows C# logic from PdfPagesTree constructor.
  Future<void> init() async {
    final catalogDict = _catalog.getPdfObject();

    if (catalogDict.containsKey(PdfName.pages)) {
      final pagesDict = await catalogDict.getAsDictionary(PdfName.pages);
      if (pagesDict == null) {
        throw PdfException(KernelExceptionMessageConstant
            .invalidPageStructurePagesMustBePdfDictionary);
      }

      // Create root PdfPages from existing Pages dictionary
      _root = PdfPages(0, pdfObject: pagesDict);
      await _root!.init();
      _parents.add(_root!);

      // Reserve null slots for pageRefs and pages based on Count
      final count = _root!.getCount();
      for (var i = 0; i < count; i++) {
        _pageRefs.add(null);
        _pages.add(null);
      }
    } else {
      // New document without pages
      _root = null;
      _parents.add(PdfPages(0));
      await _parents[0].init();
    }
  }

  int getNumberOfPages() {
    return _pageRefs.length;
  }

  /// Returns the PdfPage at the specified position (1-based index).
  Future<PdfPage?> getPage(int pageNum) async {
    if (pageNum < 1 || pageNum > getNumberOfPages()) {
      throw RangeError('Requested page number $pageNum is out of bounds.');
    }

    final index = pageNum - 1;
    var pdfPage = _pages[index];

    if (pdfPage == null) {
      await _loadPage(index);

      final pageRef = _pageRefs[index];
      if (pageRef != null) {
        final pageObject = await pageRef.getRefersTo();
        if (pageObject is PdfDictionary) {
          pdfPage = PdfPage(pageObject);
          final parentIndex = _findPageParent(index);
          pdfPage.parentPages = _parents[parentIndex];
        }
      }
      _pages[index] = pdfPage;
    }

    return pdfPage;
  }

  /// Loads page references from the pages tree for a given page index.
  Future<void> _loadPage(int pageNum,
      [Set<PdfIndirectReference>? processedParents]) async {
    processedParents ??= <PdfIndirectReference>{};

    if (_pageRefs[pageNum] != null) {
      return; // Already loaded
    }

    final parentIndex = _findPageParent(pageNum);
    final parent = _parents[parentIndex];

    final parentRef = parent.getPdfObject().getIndirectReference();
    if (parentRef != null) {
      if (processedParents.contains(parentRef)) {
        throw PdfException(
            'Invalid page structure: cyclic reference at page ${pageNum + 1}');
      }
      processedParents.add(parentRef);
    }

    final kids = parent.getKids();
    if (kids == null) {
      throw PdfException(
          'Invalid page structure: no kids at page ${pageNum + 1}');
    }

    final kidsCount = parent.getCount();
    bool findPdfPages = false;

    // Check if we have PdfPages children
    for (var i = 0; i < kids.size(); i++) {
      final kidObj = await kids.get(i, true);
      if (kidObj is PdfDictionary) {
        final pageKids = await kidObj.get(PdfName.kids, false);
        if (pageKids != null && pageKids is PdfArray) {
          findPdfPages = true;
          break;
        }
      }
    }

    if (findPdfPages) {
      // Handle nested PdfPages structure
      final newParents = <PdfPages>[];
      PdfPages? lastPdfPages;
      var remainingCount = kidsCount;

      for (var i = 0; i < kids.size() && remainingCount > 0; i++) {
        final kidRef = await kids.get(i, false);
        PdfDictionary? pdfPagesObject;

        if (kidRef is PdfIndirectReference) {
          final obj = await kidRef.getRefersTo();
          if (obj is PdfDictionary) {
            pdfPagesObject = obj;
          }
        } else if (kidRef is PdfDictionary) {
          pdfPagesObject = kidRef;
        }

        if (pdfPagesObject == null) continue;

        final childKids = await pdfPagesObject.get(PdfName.kids, false);

        if (childKids == null || childKids is! PdfArray) {
          // This is a PdfPage, not PdfPages
          if (lastPdfPages == null) {
            lastPdfPages = PdfPages(parent.getFrom(), parent: parent);
            await lastPdfPages.init();
            newParents.add(lastPdfPages);
          }
          parent.decrementCount();
          lastPdfPages.addPage(pdfPagesObject);
          remainingCount--;
        } else {
          // This is a PdfPages node
          final from = lastPdfPages == null
              ? parent.getFrom()
              : lastPdfPages.getFrom() + lastPdfPages.getCount();
          lastPdfPages =
              PdfPages(from, pdfObject: pdfPagesObject, parent: parent);
          await lastPdfPages.init();
          newParents.add(lastPdfPages);
          remainingCount -= lastPdfPages.getCount();
        }
      }

      // Replace parent with new parents
      _parents.removeAt(parentIndex);
      for (var i = newParents.length - 1; i >= 0; i--) {
        _parents.insert(parentIndex, newParents[i]);
      }

      // Recursive call to load the needed page
      await _loadPage(pageNum, processedParents);
    } else {
      // All kids are direct pages - load their references
      final from = parent.getFrom();
      final pageCount =
          parent.getCount() < kids.size() ? parent.getCount() : kids.size();

      for (var i = 0; i < pageCount; i++) {
        final kid = await kids.get(i, false);
        if (kid is PdfIndirectReference) {
          _pageRefs[from + i] = kid;
        } else if (kid is PdfDictionary) {
          _pageRefs[from + i] = kid.getIndirectReference();
        }
      }
    }
  }

  /// Binary search to find the parent PdfPages for a given page index.
  int _findPageParent(int pageNum) {
    var low = 0;
    var high = _parents.length - 1;

    while (low != high) {
      final middle = (low + high + 1) ~/ 2;
      if (_parents[middle].compareTo(pageNum) > 0) {
        high = middle - 1;
      } else {
        low = middle;
      }
    }

    return low;
  }

  Future<void> addPage(PdfPage page, PdfDocument document) async {
    PdfPages pdfPages;

    if (_root != null) {
      // In this case we save tree structure
      if (_pageRefs.isEmpty) {
        pdfPages = _root!;
      } else {
        await _loadPage(_pageRefs.length - 1);
        pdfPages = _parents[_parents.length - 1];
      }
    } else {
      // New document - create root if needed
      if (_parents.isEmpty) {
        pdfPages = PdfPages(0);
        await pdfPages.init();
        pdfPages.getPdfObject().makeIndirect(document);
        _parents.add(pdfPages);
        _root = pdfPages;
        _catalog.getPdfObject().put(PdfName.pages, _root!.getPdfObject());
      } else {
        pdfPages = _parents[_parents.length - 1];
        
        // Ensure pdfPages is indirect before using (might have been created in init)
        if (pdfPages.getPdfObject().getIndirectReference() == null) {
          pdfPages.getPdfObject().makeIndirect(document);
          _root = pdfPages;
          _catalog.getPdfObject().put(PdfName.pages, pdfPages.getPdfObject());
        }
        
        if (pdfPages.getCount() % defaultLeafSize == 0 &&
            _pageRefs.isNotEmpty) {
          pdfPages = PdfPages(pdfPages.getFrom() + pdfPages.getCount());
          await pdfPages.init();
          pdfPages.getPdfObject().makeIndirect(document);
          _parents.add(pdfPages);
        }
      }
    }

    page.getPdfObject().makeIndirect(document);
    pdfPages.addPage(page.getPdfObject());
    page.parentPages = pdfPages;

    _pageRefs.add(page.getPdfObject().getIndirectReference());
    _pages.add(page);
  }

  int getPageNumber(PdfPage page) {
    final index = _pages.indexOf(page);
    return index >= 0 ? index + 1 : 0;
  }

  /// Gets the page number for a given page dictionary.
  /// Returns 0 if not found.
  Future<int> getPageNumberByDictionary(PdfDictionary pageDictionary) async {
    final ref = pageDictionary.getIndirectReference();
    if (ref != null) {
      final idx = _pageRefs.indexOf(ref);
      if (idx >= 0) {
        return idx + 1;
      }
    }

    // If not found by reference, try loading all pages
    for (var i = 0; i < _pageRefs.length; i++) {
      if (_pageRefs[i] == null) {
        await _loadPage(i);
      }
      if (_pageRefs[i] != null && _pageRefs[i] == ref) {
        return i + 1;
      }
    }
    return 0;
  }

  /// Gets the PdfPage by its PdfDictionary.
  /// Returns null if not found.
  Future<PdfPage?> getPageByDictionary(PdfDictionary pageDictionary) async {
    final pageNum = await getPageNumberByDictionary(pageDictionary);
    if (pageNum > 0) {
      return await getPage(pageNum);
    }
    return null;
  }

  /// Inserts a PdfPage at the specified position (1-based index).
  ///
  /// [index] - The 1-based index where the page should be inserted.
  /// [page] - The PdfPage to insert.
  Future<void> addPageAt(int index, PdfPage page, PdfDocument document) async {
    // Convert to 0-based index
    final zeroBasedIndex = index - 1;

    if (zeroBasedIndex > _pageRefs.length) {
      throw RangeError('Index out of range: $index');
    }

    // If inserting at the end, use regular addPage
    if (zeroBasedIndex == _pageRefs.length) {
      await addPage(page, document);
      return;
    }

    // Load the page at the target position to ensure structure is loaded
    await _loadPage(zeroBasedIndex);

    // Make the page indirect
    page.getPdfObject().makeIndirect(document);

    // Find the parent for this position
    final parentIndex = _findPageParent(zeroBasedIndex);
    final pdfPages = _parents[parentIndex];

    // Insert page into parent (need to add method to PdfPages)
    pdfPages.addPageAt(
        zeroBasedIndex - pdfPages.getFrom(), page.getPdfObject());
    page.parentPages = pdfPages;

    // Correct 'from' properties of subsequent parents
    _correctPdfPagesFromProperty(parentIndex + 1, 1);

    // Insert into our tracking lists
    _pageRefs.insert(
        zeroBasedIndex, page.getPdfObject().getIndirectReference());
    _pages.insert(zeroBasedIndex, page);
  }

  /// Removes the page at the specified position (1-based index).
  /// Returns the page that was removed, or null if removal failed.
  Future<PdfPage?> removePage(int pageNum) async {
    if (pageNum < 1 || pageNum > _pageRefs.length) {
      return null;
    }

    final pdfPage = await getPage(pageNum);
    if (pdfPage == null) {
      return null;
    }

    final zeroBasedIndex = pageNum - 1;

    // Find parent and remove from it
    final parentIndex = _findPageParent(zeroBasedIndex);
    final pdfPages = _parents[parentIndex];

    // Remove page from parent's Kids array
    if (pdfPages.removePage(zeroBasedIndex)) {
      // If parent has no more pages, remove it
      if (pdfPages.getCount() == 0) {
        _parents.removeAt(parentIndex);
        // Note: In a more complete implementation, we'd also need to
        // update parent references in the PDF structure
      }

      // Correct 'from' properties of subsequent parents
      _correctPdfPagesFromProperty(parentIndex + 1, -1);

      // Remove from our tracking lists
      _pageRefs.removeAt(zeroBasedIndex);
      _pages.removeAt(zeroBasedIndex);

      return pdfPage;
    }

    return null;
  }

  /// Corrects the 'from' property of PdfPages starting from the given index.
  void _correctPdfPagesFromProperty(int index, int correction) {
    for (var i = index; i < _parents.length; i++) {
      _parents[i].correctFrom(correction);
    }
  }

  /// Generate PdfPages tree - returns root PdfObject.
  Future<PdfObject> generateTree() async {
    if (_pageRefs.isEmpty && _document != null) {
      await _document!.addNewPage();
    }

    if (_generated) {
      throw PdfException('PDF pages tree could be generated only once.');
    }

    if (_root == null) {
      while (_parents.length != 1) {
        final nextParents = <PdfPages>[];
        var dynamicLeafSize = defaultLeafSize;
        PdfPages? current;

        for (var i = 0; i < _parents.length; i++) {
          final pages = _parents[i];
          final pageCount = pages.getCount();

          if (i % dynamicLeafSize == 0) {
            if (pageCount <= 1) {
              dynamicLeafSize++;
            } else {
              current = PdfPages(-1);
              await current.init();
              if (_document != null) {
                current.getPdfObject().makeIndirect(_document!);
              }
              nextParents.add(current);
              dynamicLeafSize = defaultLeafSize;
            }
          }
          current?.addPages(pages);
        }
        _parents.clear();
        _parents.addAll(nextParents);
      }
      _root = _parents[0];
    }

    _generated = true;
    return _root!.getPdfObject();
  }
}

class AtomicInteger {
  int value;
  AtomicInteger(this.value);
  void decrement() => value--;
  void add(int v) => value += v;
}
