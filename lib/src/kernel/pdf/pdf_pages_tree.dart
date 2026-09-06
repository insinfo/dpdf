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
class CraftPdfPagesTree {
  static const int defaultLeafSize = 10;

  final List<CraftPdfIndirectReference?> _pageRefs = [];
  final List<CraftPdfPage?> _pages = [];
  final List<CraftPdfPages> _parents = [];
  CraftPdfPages? _root;
  final CraftPdfCatalog _catalog;
  CraftPdfDocument? _document;
  bool _generated = false;

  CraftPdfPagesTree(this._catalog);

  /// Sets the document reference
  void setDocument(CraftPdfDocument doc) {
    _document = doc;
  }

  /// Initializes the pages tree by reading the tree structure from the catalog.
  /// Follows C# logic from PdfPagesTree constructor.
  Future<void> init() async {
    final catalogDict = _catalog.pdfRepresentation();

    if (catalogDict.containsKey(CraftPdfName.pages)) {
      final pagesDict = await catalogDict.dictionaryEntry(CraftPdfName.pages);
      if (pagesDict == null) {
        throw CraftPdfException(CraftKernelExceptionMessageConstant
            .invalidPageStructurePagesMustBePdfDictionary);
      }

      // Create root PdfPages from existing Pages dictionary
      _root = CraftPdfPages(0, pdfObject: pagesDict);
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
      _parents.add(CraftPdfPages(0));
      await _parents[0].init();
    }
  }

  int pageTotal() {
    return _pageRefs.length;
  }

  /// Returns the PdfPage at the specified position (1-based index).
  Future<CraftPdfPage?> pageAt(int pageNum) async {
    if (pageNum < 1 || pageNum > pageTotal()) {
      throw RangeError('Requested page number $pageNum is out of bounds.');
    }

    final index = pageNum - 1;
    var pdfPage = _pages[index];

    if (pdfPage == null) {
      await _loadPage(index);

      final pageRef = _pageRefs[index];
      if (pageRef != null) {
        final pageObject = await pageRef.targetObject();
        if (pageObject is CraftPdfDictionary) {
          pdfPage = CraftPdfPage(pageObject);
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
      [Set<CraftPdfIndirectReference>? processedParents]) async {
    processedParents ??= <CraftPdfIndirectReference>{};

    if (_pageRefs[pageNum] != null) {
      return; // Already loaded
    }

    final parentIndex = _findPageParent(pageNum);
    final parent = _parents[parentIndex];

    final parentRef = parent.pdfRepresentation().indirectHandle();
    if (parentRef != null) {
      if (processedParents.contains(parentRef)) {
        throw CraftPdfException(
            'Invalid page structure: cyclic reference at page ${pageNum + 1}');
      }
      processedParents.add(parentRef);
    }

    final kids = parent.getKids();
    if (kids == null) {
      throw CraftPdfException(
          'Invalid page structure: no kids at page ${pageNum + 1}');
    }

    final kidsCount = parent.getCount();
    bool findPdfPages = false;

    // Check if we have PdfPages children
    for (var i = 0; i < kids.size(); i++) {
      final kidObj = await kids.get(i, true);
      if (kidObj is CraftPdfDictionary) {
        final pageKids = await kidObj.get(CraftPdfName.kids, false);
        if (pageKids != null && pageKids is CraftPdfArray) {
          findPdfPages = true;
          break;
        }
      }
    }

    if (findPdfPages) {
      // Handle nested PdfPages structure
      final newParents = <CraftPdfPages>[];
      CraftPdfPages? lastPdfPages;
      var remainingCount = kidsCount;

      for (var i = 0; i < kids.size() && remainingCount > 0; i++) {
        final kidRef = await kids.get(i, false);
        CraftPdfDictionary? pdfPagesObject;

        if (kidRef is CraftPdfIndirectReference) {
          final obj = await kidRef.targetObject();
          if (obj is CraftPdfDictionary) {
            pdfPagesObject = obj;
          }
        } else if (kidRef is CraftPdfDictionary) {
          pdfPagesObject = kidRef;
        }

        if (pdfPagesObject == null) continue;

        final childKids = await pdfPagesObject.get(CraftPdfName.kids, false);

        if (childKids == null || childKids is! CraftPdfArray) {
          // This is a PdfPage, not PdfPages
          if (lastPdfPages == null) {
            lastPdfPages = CraftPdfPages(parent.getFrom(), parent: parent);
            await lastPdfPages.init();
            newParents.add(lastPdfPages);
          }
          parent.decrementCount();
          lastPdfPages.appendPageObject(pdfPagesObject);
          remainingCount--;
        } else {
          // This is a PdfPages node
          final from = lastPdfPages == null
              ? parent.getFrom()
              : lastPdfPages.getFrom() + lastPdfPages.getCount();
          lastPdfPages =
              CraftPdfPages(from, pdfObject: pdfPagesObject, parent: parent);
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
        if (kid is CraftPdfIndirectReference) {
          _pageRefs[from + i] = kid;
        } else if (kid is CraftPdfDictionary) {
          _pageRefs[from + i] = kid.indirectHandle();
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

  Future<void> appendPageObject(
      CraftPdfPage page, CraftPdfDocument document) async {
    CraftPdfPages pdfPages;

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
        pdfPages = CraftPdfPages(0);
        await pdfPages.init();
        pdfPages.pdfRepresentation().attachToDocument(document);
        _parents.add(pdfPages);
        _root = pdfPages;
        _catalog
            .pdfRepresentation()
            .put(CraftPdfName.pages, _root!.pdfRepresentation());
      } else {
        pdfPages = _parents[_parents.length - 1];

        // Ensure pdfPages is indirect before using (might have been created in init)
        if (pdfPages.pdfRepresentation().indirectHandle() == null) {
          pdfPages.pdfRepresentation().attachToDocument(document);
          _root = pdfPages;
          _catalog
              .pdfRepresentation()
              .put(CraftPdfName.pages, pdfPages.pdfRepresentation());
        }

        if (pdfPages.getCount() % defaultLeafSize == 0 &&
            _pageRefs.isNotEmpty) {
          pdfPages = CraftPdfPages(pdfPages.getFrom() + pdfPages.getCount());
          await pdfPages.init();
          pdfPages.pdfRepresentation().attachToDocument(document);
          _parents.add(pdfPages);
        }
      }
    }

    page.pdfRepresentation().attachToDocument(document);
    pdfPages.appendPageObject(page.pdfRepresentation());
    page.parentPages = pdfPages;

    _pageRefs.add(page.pdfRepresentation().indirectHandle());
    _pages.add(page);
  }

  int pageOrdinal(CraftPdfPage page) {
    final index = _pages.indexOf(page);
    return index >= 0 ? index + 1 : 0;
  }

  /// Gets the page number for a given page dictionary.
  /// Returns 0 if not found.
  Future<int> getPageNumberByDictionary(
      CraftPdfDictionary pageDictionary) async {
    final ref = pageDictionary.indirectHandle();
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
  Future<CraftPdfPage?> findPageObject(
      CraftPdfDictionary pageDictionary) async {
    final pageNum = await getPageNumberByDictionary(pageDictionary);
    if (pageNum > 0) {
      return await pageAt(pageNum);
    }
    return null;
  }

  /// Inserts a PdfPage at the specified position (1-based index).
  ///
  /// [index] - The 1-based index where the page should be inserted.
  /// [page] - The PdfPage to insert.
  Future<void> insertPageObject(
      int index, CraftPdfPage page, CraftPdfDocument document) async {
    // Convert to 0-based index
    final zeroBasedIndex = index - 1;

    if (zeroBasedIndex > _pageRefs.length) {
      throw RangeError('Index out of range: $index');
    }

    // If inserting at the end, use regular addPage
    if (zeroBasedIndex == _pageRefs.length) {
      await appendPageObject(page, document);
      return;
    }

    // Load the page at the target position to ensure structure is loaded
    await _loadPage(zeroBasedIndex);

    // Make the page indirect
    page.pdfRepresentation().attachToDocument(document);

    // Find the parent for this position
    final parentIndex = _findPageParent(zeroBasedIndex);
    final pdfPages = _parents[parentIndex];

    // Insert page into parent (need to add method to PdfPages)
    pdfPages.insertPageObject(
        zeroBasedIndex - pdfPages.getFrom(), page.pdfRepresentation());
    page.parentPages = pdfPages;

    // Correct 'from' properties of subsequent parents
    _correctPdfPagesFromProperty(parentIndex + 1, 1);

    // Insert into our tracking lists
    _pageRefs.insert(zeroBasedIndex, page.pdfRepresentation().indirectHandle());
    _pages.insert(zeroBasedIndex, page);
  }

  /// Removes the page at the specified position (1-based index).
  /// Returns the page that was removed, or null if removal failed.
  Future<CraftPdfPage?> detachPage(int pageNum) async {
    if (pageNum < 1 || pageNum > _pageRefs.length) {
      return null;
    }

    final pdfPage = await pageAt(pageNum);
    if (pdfPage == null) {
      return null;
    }

    final zeroBasedIndex = pageNum - 1;

    // Find parent and remove from it
    final parentIndex = _findPageParent(zeroBasedIndex);
    final pdfPages = _parents[parentIndex];

    // Remove page from parent's Kids array
    if (pdfPages.detachPage(zeroBasedIndex)) {
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
  Future<CraftPdfObject> generateTree() async {
    if (_pageRefs.isEmpty && _document != null) {
      await _document!.appendBlankPage();
    }

    if (_generated) {
      throw CraftPdfException('PDF pages tree could be generated only once.');
    }

    if (_root == null) {
      while (_parents.length != 1) {
        final nextParents = <CraftPdfPages>[];
        var dynamicLeafSize = defaultLeafSize;
        CraftPdfPages? current;

        for (var i = 0; i < _parents.length; i++) {
          final pages = _parents[i];
          final pageCount = pages.getCount();

          if (i % dynamicLeafSize == 0) {
            if (pageCount <= 1) {
              dynamicLeafSize++;
            } else {
              current = CraftPdfPages(-1);
              await current.init();
              if (_document != null) {
                current.pdfRepresentation().attachToDocument(_document!);
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
    return _root!.pdfRepresentation();
  }
}

class AtomicInteger {
  int value;
  AtomicInteger(this.value);
  void decrement() => value--;
  void add(int v) => value += v;
}
