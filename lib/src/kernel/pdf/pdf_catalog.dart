import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_object_wrapper.dart';
import 'pdf_pages_tree.dart';
import 'pdf_object.dart';
import '../exceptions/pdf_exception.dart';
import 'pdf_page.dart';
import 'pdf_string.dart';
import 'pdf_outline.dart';
import 'pdf_name_tree.dart';
import 'pdf_document.dart';
import 'pdf_array.dart';
import 'pdf_boolean.dart';
import 'pdf_stream.dart';

/// The root of a document’s object hierarchy.
class PdfCatalog extends PdfObjectWrapper<PdfDictionary> {
  late final PdfPagesTree _pageTree;

  PdfCatalog(PdfDictionary pdfObject) : super(pdfObject) {
    // ignore: unnecessary_null_comparison
    if (pdfObject == null) {
      throw PdfException('Document has no PDF catalog object.');
    }
    _pageTree = PdfPagesTree(this);
  }

  /// Initializes the catalog and its components (like the pages tree).
  Future<void> init() async {
    getPdfObject().put(PdfName.type, PdfName.catalog);
    setForbidRelease();
    await _pageTree.init();
  }

  PdfPagesTree getPageTree() => _pageTree;

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  /// Gets page mode of the document.
  Future<PdfName?> getPageMode() async {
    return await getPdfObject().getAsName(PdfName.pageMode);
  }

  /// Sets page mode.
  PdfCatalog setPageMode(PdfName pageMode) {
    getPdfObject().put(PdfName.pageMode, pageMode);
    return this;
  }

  /// Gets page layout.
  Future<PdfName?> getPageLayout() async {
    return await getPdfObject().getAsName(PdfName.pageLayout);
  }

  /// Sets page layout.
  PdfCatalog setPageLayout(PdfName pageLayout) {
    getPdfObject().put(PdfName.pageLayout, pageLayout);
    return this;
  }

  /// Sets viewer preferences.
  PdfCatalog setViewerPreferences(PdfDictionary preferences) {
    getPdfObject().put(PdfName.viewerPreferences, preferences);
    return this;
  }

  /// Convenience method to set DisplayDocTitle.
  PdfCatalog setDisplayDocTitle(bool display) {
    var prefsObj = getPdfObject().getMap()?[PdfName.viewerPreferences];
    PdfDictionary prefs;
    if (prefsObj is! PdfDictionary) {
      prefs = PdfDictionary();
      getPdfObject().put(PdfName.viewerPreferences, prefs);
      final doc = getPdfObject().getIndirectReference()?.getDocument();
      if (doc != null) {
        prefs.makeIndirect(doc);
      }
    } else {
      prefs = prefsObj;
    }
    prefs.put(PdfName.displayDocTitle, PdfBoolean(display));
    return this;
  }

  PdfOutline? _outlines;
  final Map<PdfObject, List<PdfOutline>> _pagesWithOutlines = {};
  bool _outlineMode = false;

  /// Returns true if the document is in outline mode.
  bool isOutlineMode() => _outlineMode;

  /// Removes outlines associated with the page.
  Future<void> removeOutlines(PdfPage page) async {
    final doc = getPdfObject().getIndirectReference()?.getDocument();
    if (doc == null || doc.getWriter() == null) {
      return;
    }
    if (hasOutlines()) {
      await getOutlines(false);
      if (_pagesWithOutlines.isNotEmpty) {
        final outlines = _pagesWithOutlines[page.getPdfObject()];
        if (outlines != null) {
          for (final outline in List<PdfOutline>.from(outlines)) {
            outline.removeOutline();
          }
        }
      }
    }
  }

  /// Gets the outlines of the document.
  Future<PdfOutline?> getOutlines(bool updateOutlines) async {
    if (_outlines != null && !updateOutlines) {
      return _outlines;
    }
    if (_outlines != null) {
      _outlines!.clear();
      _pagesWithOutlines.clear();
    }
    _outlineMode = true;
    final outlineRoot = await getPdfObject().getAsDictionary(PdfName.outlines);
    final doc = getPdfObject().getIndirectReference()?.getDocument();

    if (outlineRoot == null) {
      if (doc?.getWriter() == null) {
        return null;
      }
      _outlines = PdfOutline.createRoot(doc!);
    } else {
      if (doc == null) {
         return null;
      }
      await _constructOutlines(outlineRoot, doc);
    }
    return _outlines;
  }

  Future<void> _constructOutlines(
      PdfDictionary outlineRoot, PdfDocument document) async {
    _outlines = PdfOutline.wrap(outlineRoot, document);

    final stack = <_OutlineProcessingItem>[];

    final first = await outlineRoot.getAsDictionary(PdfName.first);
    if (first != null) {
      stack.add(_OutlineProcessingItem(first, _outlines!));
    }

    final visited = <PdfDictionary>{};

    while (stack.isNotEmpty) {
      final item = stack.removeLast();
      final currentDict = item.dictionary;
      final parentOutline = item.parent;

      if (visited.contains(currentDict)) continue;
      visited.add(currentDict);

      final title = await currentDict.getAsString(PdfName.title);
      final currentOutline = PdfOutline.wrap(currentDict, document);
      if (title != null && currentOutline.getTitle() == null) {
        currentOutline.setTitle(title.toUnicodeString());
      }
      
      parentOutline.getAllChildren().add(currentOutline);
      _addOutlineToPage(currentOutline, currentDict);

      // Next sibling
      final next = await currentDict.getAsDictionary(PdfName.next);
      if (next != null) {
        stack.add(_OutlineProcessingItem(next, parentOutline));
      }

      // First child
      final child = await currentDict.getAsDictionary(PdfName.first);
      if (child != null) {
        stack.add(_OutlineProcessingItem(child, currentOutline));
      }
    }
  }

  void _addOutlineToPage(PdfOutline outline, PdfDictionary outlineDict) {
    var dest = outlineDict.getMap()?[PdfName.dest];
    if (dest == null) {
      final a = outlineDict.getMap()?[PdfName.a];
      if (a is PdfDictionary && PdfName.goTo == a.getMap()?[PdfName.s]) {
        dest = a.getMap()?[PdfName.d];
      }
    }

    if (dest != null) {
      if (dest is PdfIndirectReference) {
        dest = dest.getRefersToSync();
      }
      if (dest is PdfArray) {
        final pageRef = dest.toList().isNotEmpty ? dest.toList()[0] : null;
        if (pageRef is PdfIndirectReference) {
          final pageObj = pageRef.getRefersToSync();
          if (pageObj != null) {
            _pagesWithOutlines.putIfAbsent(pageObj, () => []).add(outline);
          }
        }
      }
    }
  }

  /// Indicates if the document has any outlines.
  bool hasOutlines() {
    return getPdfObject().containsKey(PdfName.outlines);
  }

  /// Registers an outline with a page for removal tracking.
  void registerOutlineWithPage(PdfOutline outline, PdfObject pageObj) {
    _pagesWithOutlines.putIfAbsent(pageObj, () => []).add(outline);
  }

  /// Adds a named destination.
  Future<void> addNamedDestination(PdfString key, PdfObject value) async {
    final tree = await PdfNameTree.create(this, PdfName.dests);
    tree.addEntry(key, value);
    final treeDict = tree.buildTree();

    PdfDictionary? names = await getPdfObject().getAsDictionary(PdfName.names);
    if (names == null) {
      names = PdfDictionary();
      put(PdfName.names, names);
      final doc = getPdfObject().getIndirectReference()?.getDocument();
      if (doc != null) {
        names.makeIndirect(doc);
      }
    }
    names.put(PdfName.dests, treeDict);
    names.setModified();
  }

  /// Adds a name to a NameTree.
  Future<void> addNameToNameTree(
      PdfString key, PdfObject value, PdfName treeName) async {
    final tree = await PdfNameTree.create(this, treeName);
    tree.addEntry(key, value);
    final treeDict = tree.buildTree();

    PdfDictionary? names = await getPdfObject().getAsDictionary(PdfName.names);
    if (names == null) {
      names = PdfDictionary();
      put(PdfName.names, names);
      final doc = getPdfObject().getIndirectReference()?.getDocument();
      if (doc != null) {
        names.makeIndirect(doc);
      }
    }
    names.put(treeName, treeDict);
    names.setModified();
  }

  /// Gets the metadata stream from the catalog.
  Future<PdfStream?> getMetadata() async {
    return await getPdfObject().getAsStream(PdfName.metadata);
  }

  /// Sets the metadata stream for the document.
  PdfCatalog setMetadata(PdfStream metadata) {
    put(PdfName.metadata, metadata);
    return this;
  }

  /// Gets the OutputIntents array.
  Future<PdfArray?> getOutputIntents() async {
    return await getPdfObject().getAsArray(PdfName.outputIntents);
  }

  /// Adds an output intent to the document.
  PdfCatalog addOutputIntent(PdfObject outputIntent) {
    PdfArray? intents = getPdfObject().getMap()?[PdfName.outputIntents] as PdfArray?;
    if (intents == null) {
      intents = PdfArray();
      final doc = getPdfObject().getIndirectReference()?.getDocument();
      if (doc != null) {
        intents.makeIndirect(doc);
      }
      put(PdfName.outputIntents, intents);
    }
    intents.add(outputIntent);
    intents.setModified();
    return this;
  }

  void put(PdfName key, PdfObject value) {
    getPdfObject().put(key, value);
    setModified();
  }
}

class _OutlineProcessingItem {
  final PdfDictionary dictionary;
  final PdfOutline parent;
  _OutlineProcessingItem(this.dictionary, this.parent);
}
