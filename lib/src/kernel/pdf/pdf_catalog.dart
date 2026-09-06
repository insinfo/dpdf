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
class CraftPdfCatalog extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  late final CraftPdfPagesTree _pageTree;

  CraftPdfCatalog(CraftPdfDictionary pdfObject) : super(pdfObject) {
    // ignore: unnecessary_null_comparison
    if (pdfObject == null) {
      throw CraftPdfException('Document has no PDF catalog object.');
    }
    _pageTree = CraftPdfPagesTree(this);
  }

  /// Initializes the catalog and its components (like the pages tree).
  Future<void> init() async {
    pdfRepresentation().put(CraftPdfName.type, CraftPdfName.catalog);
    setForbidRelease();
    await _pageTree.init();
  }

  CraftPdfPagesTree getPageTree() => _pageTree;

  @override
  bool requiresIndirectStorage() => true;

  /// Gets page mode of the document.
  Future<CraftPdfName?> getPageMode() async {
    return await pdfRepresentation().nameEntry(CraftPdfName.pageMode);
  }

  /// Sets page mode.
  CraftPdfCatalog setPageMode(CraftPdfName pageMode) {
    pdfRepresentation().put(CraftPdfName.pageMode, pageMode);
    return this;
  }

  /// Gets page layout.
  Future<CraftPdfName?> getPageLayout() async {
    return await pdfRepresentation().nameEntry(CraftPdfName.pageLayout);
  }

  /// Sets page layout.
  CraftPdfCatalog setPageLayout(CraftPdfName pageLayout) {
    pdfRepresentation().put(CraftPdfName.pageLayout, pageLayout);
    return this;
  }

  /// Sets viewer preferences.
  CraftPdfCatalog setViewerPreferences(CraftPdfDictionary preferences) {
    pdfRepresentation().put(CraftPdfName.viewerPreferences, preferences);
    return this;
  }

  /// Convenience method to set DisplayDocTitle.
  CraftPdfCatalog setDisplayDocTitle(bool display) {
    var prefsObj =
        pdfRepresentation().getMap()?[CraftPdfName.viewerPreferences];
    CraftPdfDictionary prefs;
    if (prefsObj is! CraftPdfDictionary) {
      prefs = CraftPdfDictionary();
      pdfRepresentation().put(CraftPdfName.viewerPreferences, prefs);
      final doc = pdfRepresentation().indirectHandle()?.getDocument();
      if (doc != null) {
        prefs.attachToDocument(doc);
      }
    } else {
      prefs = prefsObj;
    }
    prefs.put(CraftPdfName.displayDocTitle, CraftPdfBoolean(display));
    return this;
  }

  CraftPdfOutline? _outlines;
  final Map<CraftPdfObject, List<CraftPdfOutline>> _pagesWithOutlines = {};
  bool _outlineMode = false;

  /// Returns true if the document is in outline mode.
  bool isOutlineMode() => _outlineMode;

  /// Removes outlines associated with the page.
  Future<void> removeOutlines(CraftPdfPage page) async {
    final doc = pdfRepresentation().indirectHandle()?.getDocument();
    if (doc == null || doc.outputWriter() == null) {
      return;
    }
    if (containsOutlineTree()) {
      await outlineTree(false);
      if (_pagesWithOutlines.isNotEmpty) {
        final outlines = _pagesWithOutlines[page.pdfRepresentation()];
        if (outlines != null) {
          for (final outline in List<CraftPdfOutline>.from(outlines)) {
            outline.removeOutline();
          }
        }
      }
    }
  }

  /// Gets the outlines of the document.
  Future<CraftPdfOutline?> outlineTree(bool updateOutlines) async {
    if (_outlines != null && !updateOutlines) {
      return _outlines;
    }
    if (_outlines != null) {
      _outlines!.clear();
      _pagesWithOutlines.clear();
    }
    _outlineMode = true;
    final outlineRoot =
        await pdfRepresentation().dictionaryEntry(CraftPdfName.outlines);
    final doc = pdfRepresentation().indirectHandle()?.getDocument();

    if (outlineRoot == null) {
      if (doc?.outputWriter() == null) {
        return null;
      }
      _outlines = CraftPdfOutline.createRoot(doc!);
    } else {
      if (doc == null) {
        return null;
      }
      await _constructOutlines(outlineRoot, doc);
    }
    return _outlines;
  }

  Future<void> _constructOutlines(
      CraftPdfDictionary outlineRoot, CraftPdfDocument document) async {
    _outlines = CraftPdfOutline.wrap(outlineRoot, document);

    final stack = <_OutlineProcessingItem>[];

    final first = await outlineRoot.dictionaryEntry(CraftPdfName.first);
    if (first != null) {
      stack.add(_OutlineProcessingItem(first, _outlines!));
    }

    final visited = <CraftPdfDictionary>{};

    while (stack.isNotEmpty) {
      final item = stack.removeLast();
      final currentDict = item.dictionary;
      final parentOutline = item.parent;

      if (visited.contains(currentDict)) continue;
      visited.add(currentDict);

      final title = await currentDict.stringEntry(CraftPdfName.title);
      final currentOutline = CraftPdfOutline.wrap(currentDict, document);
      if (title != null && currentOutline.getTitle() == null) {
        currentOutline.setTitle(title.decodeMappingText());
      }

      parentOutline.getAllChildren().add(currentOutline);
      _addOutlineToPage(currentOutline, currentDict);

      // Next sibling
      final next = await currentDict.dictionaryEntry(CraftPdfName.next);
      if (next != null) {
        stack.add(_OutlineProcessingItem(next, parentOutline));
      }

      // First child
      final child = await currentDict.dictionaryEntry(CraftPdfName.first);
      if (child != null) {
        stack.add(_OutlineProcessingItem(child, currentOutline));
      }
    }
  }

  void _addOutlineToPage(
      CraftPdfOutline outline, CraftPdfDictionary outlineDict) {
    var dest = outlineDict.getMap()?[CraftPdfName.dest];
    if (dest == null) {
      final a = outlineDict.getMap()?[CraftPdfName.a];
      if (a is CraftPdfDictionary &&
          CraftPdfName.goTo == a.getMap()?[CraftPdfName.s]) {
        dest = a.getMap()?[CraftPdfName.d];
      }
    }

    if (dest != null) {
      if (dest is CraftPdfIndirectReference) {
        dest = dest.targetObjectSync();
      }
      if (dest is CraftPdfArray) {
        final pageRef = dest.toList().isNotEmpty ? dest.toList()[0] : null;
        if (pageRef is CraftPdfIndirectReference) {
          final pageObj = pageRef.targetObjectSync();
          if (pageObj != null) {
            _pagesWithOutlines.putIfAbsent(pageObj, () => []).add(outline);
          }
        }
      }
    }
  }

  /// Indicates if the document has any outlines.
  bool containsOutlineTree() {
    return pdfRepresentation().containsKey(CraftPdfName.outlines);
  }

  /// Registers an outline with a page for removal tracking.
  void registerOutlineWithPage(
      CraftPdfOutline outline, CraftPdfObject pageObj) {
    _pagesWithOutlines.putIfAbsent(pageObj, () => []).add(outline);
  }

  /// Adds a named destination.
  Future<void> registerDestination(
      CraftPdfString key, CraftPdfObject value) async {
    final tree = await CraftPdfNameTree.create(this, CraftPdfName.dests);
    tree.addEntry(key, value);
    final treeDict = tree.buildTree();

    CraftPdfDictionary? names =
        await pdfRepresentation().dictionaryEntry(CraftPdfName.names);
    if (names == null) {
      names = CraftPdfDictionary();
      put(CraftPdfName.names, names);
      final doc = pdfRepresentation().indirectHandle()?.getDocument();
      if (doc != null) {
        names.attachToDocument(doc);
      }
    }
    names.put(CraftPdfName.dests, treeDict);
    names.markChanged();
  }

  /// Adds a name to a NameTree.
  Future<void> addNameToNameTree(
      CraftPdfString key, CraftPdfObject value, CraftPdfName treeName) async {
    final tree = await CraftPdfNameTree.create(this, treeName);
    tree.addEntry(key, value);
    final treeDict = tree.buildTree();

    CraftPdfDictionary? names =
        await pdfRepresentation().dictionaryEntry(CraftPdfName.names);
    if (names == null) {
      names = CraftPdfDictionary();
      put(CraftPdfName.names, names);
      final doc = pdfRepresentation().indirectHandle()?.getDocument();
      if (doc != null) {
        names.attachToDocument(doc);
      }
    }
    names.put(treeName, treeDict);
    names.markChanged();
  }

  /// Gets the metadata stream from the catalog.
  Future<CraftPdfStream?> getMetadata() async {
    return await pdfRepresentation().streamEntry(CraftPdfName.metadata);
  }

  /// Sets the metadata stream for the document.
  CraftPdfCatalog setMetadata(CraftPdfStream metadata) {
    put(CraftPdfName.metadata, metadata);
    return this;
  }

  /// Gets the OutputIntents array.
  Future<CraftPdfArray?> getOutputIntents() async {
    return await pdfRepresentation().arrayEntry(CraftPdfName.outputIntents);
  }

  /// Adds an output intent to the document.
  CraftPdfCatalog registerOutputProfile(CraftPdfObject outputIntent) {
    CraftPdfArray? intents = pdfRepresentation()
        .getMap()?[CraftPdfName.outputIntents] as CraftPdfArray?;
    if (intents == null) {
      intents = CraftPdfArray();
      final doc = pdfRepresentation().indirectHandle()?.getDocument();
      if (doc != null) {
        intents.attachToDocument(doc);
      }
      put(CraftPdfName.outputIntents, intents);
    }
    intents.add(outputIntent);
    intents.markChanged();
    return this;
  }

  void put(CraftPdfName key, CraftPdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
  }
}

class _OutlineProcessingItem {
  final CraftPdfDictionary dictionary;
  final CraftPdfOutline parent;
  _OutlineProcessingItem(this.dictionary, this.parent);
}
