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
import 'pdf_version.dart';
import 'article/pdf_article_thread.dart';
import 'viewer/pdf_legal_attestation.dart';
import 'viewer/pdf_mark_info.dart';
import 'viewer/pdf_page_layout.dart';
import 'viewer/pdf_page_piece.dart';
import 'viewer/pdf_requirement.dart';
import 'viewer/pdf_uri_dictionary.dart';
import 'viewer/pdf_viewer_preferences.dart';

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
    pdfRepresentation().put(PdfName.type, PdfName.catalog);
    setForbidRelease();
    await _pageTree.init();
  }

  PdfPagesTree getPageTree() => _pageTree;

  @override
  bool requiresIndirectStorage() => true;

  /// Gets page mode of the document.
  Future<PdfName?> getPageMode() async {
    return await pdfRepresentation().nameEntry(PdfName.pageMode);
  }

  /// Sets page mode.
  PdfCatalog setPageMode(PdfName pageMode) {
    pdfRepresentation().put(PdfName.pageMode, pageMode);
    return this;
  }

  /// Gets page layout.
  Future<PdfName?> getPageLayout() async {
    return await pdfRepresentation().nameEntry(PdfName.pageLayout);
  }

  /// Sets page layout.
  PdfCatalog setPageLayout(PdfName pageLayout) {
    pdfRepresentation().put(PdfName.pageLayout, pageLayout);
    return this;
  }

  /// Sets viewer preferences.
  PdfCatalog setViewerPreferences(PdfDictionary preferences) {
    pdfRepresentation().put(PdfName.viewerPreferences, preferences);
    return this;
  }

  /// Installs [preferences] as `/ViewerPreferences` (12.2, Table 150).
  PdfCatalog setViewerPreferencesDictionary(PdfViewerPreferences preferences) {
    put(PdfName.viewerPreferences, preferences.pdfRepresentation());
    return this;
  }

  /// Gets `/ViewerPreferences` (12.2, Table 150), or `null` when the catalog
  /// carries none. Table 150 then lets the reader use its own settings.
  Future<PdfViewerPreferences?> getViewerPreferences() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfName.viewerPreferences);
    return dictionary == null ? null : PdfViewerPreferences(dictionary);
  }

  /// Gets `/ViewerPreferences`, creating and installing an empty dictionary
  /// when the catalog has none yet.
  Future<PdfViewerPreferences> viewerPreferences() async {
    final existing = await getViewerPreferences();
    if (existing != null) return existing;
    final created = PdfViewerPreferences();
    setViewerPreferencesDictionary(created);
    return created;
  }

  /// Convenience method to set DisplayDocTitle.
  PdfCatalog setDisplayDocTitle(bool display) {
    var prefsObj = pdfRepresentation().getMap()?[PdfName.viewerPreferences];
    if (prefsObj is PdfIndirectReference) {
      prefsObj = prefsObj.targetObjectSync();
    }
    PdfDictionary prefs;
    if (prefsObj is! PdfDictionary) {
      prefs = PdfDictionary();
      pdfRepresentation().put(PdfName.viewerPreferences, prefs);
      final doc = pdfRepresentation().indirectHandle()?.getDocument();
      if (doc != null) {
        prefs.attachToDocument(doc);
      }
    } else {
      prefs = prefsObj;
    }
    prefs.put(PdfName.displayDocTitle, PdfBoolean(display));
    prefs.markChanged();
    return this;
  }

  PdfOutline? _outlines;
  final Map<PdfObject, List<PdfOutline>> _pagesWithOutlines = {};
  bool _outlineMode = false;

  /// Returns true if the document is in outline mode.
  bool isOutlineMode() => _outlineMode;

  /// Removes outlines associated with the page.
  Future<void> removeOutlines(PdfPage page) async {
    final doc = pdfRepresentation().indirectHandle()?.getDocument();
    if (doc == null || doc.outputWriter() == null) {
      return;
    }
    if (containsOutlineTree()) {
      await outlineTree(false);
      if (_pagesWithOutlines.isNotEmpty) {
        final outlines = _pagesWithOutlines[page.pdfRepresentation()];
        if (outlines != null) {
          for (final outline in List<PdfOutline>.from(outlines)) {
            outline.removeOutline();
          }
        }
      }
    }
  }

  /// Gets the outlines of the document.
  Future<PdfOutline?> outlineTree(bool updateOutlines) async {
    if (_outlines != null && !updateOutlines) {
      return _outlines;
    }
    if (_outlines != null) {
      _outlines!.clear();
      _pagesWithOutlines.clear();
    }
    _outlineMode = true;
    final outlineRoot =
        await pdfRepresentation().dictionaryEntry(PdfName.outlines);
    final doc = pdfRepresentation().indirectHandle()?.getDocument();

    if (outlineRoot == null) {
      if (doc?.outputWriter() == null) {
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

    final first = await outlineRoot.dictionaryEntry(PdfName.first);
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

      final title = await currentDict.stringEntry(PdfName.title);
      final currentOutline = PdfOutline.wrap(currentDict, document);
      if (title != null && currentOutline.getTitle() == null) {
        currentOutline.setTitle(title.decodeMappingText());
      }

      parentOutline.getAllChildren().add(currentOutline);
      _addOutlineToPage(currentOutline, currentDict);

      // Next sibling
      final next = await currentDict.dictionaryEntry(PdfName.next);
      if (next != null) {
        stack.add(_OutlineProcessingItem(next, parentOutline));
      }

      // First child
      final child = await currentDict.dictionaryEntry(PdfName.first);
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
        dest = dest.targetObjectSync();
      }
      if (dest is PdfArray) {
        final pageRef = dest.toList().isNotEmpty ? dest.toList()[0] : null;
        if (pageRef is PdfIndirectReference) {
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
    return pdfRepresentation().containsKey(PdfName.outlines);
  }

  /// Registers an outline with a page for removal tracking.
  void registerOutlineWithPage(PdfOutline outline, PdfObject pageObj) {
    _pagesWithOutlines.putIfAbsent(pageObj, () => []).add(outline);
  }

  /// Adds a named destination.
  Future<void> registerDestination(PdfString key, PdfObject value) async {
    final tree = await PdfNameTree.create(this, PdfName.dests);
    tree.addEntry(key, value);
    final treeDict = tree.buildTree();

    PdfDictionary? names =
        await pdfRepresentation().dictionaryEntry(PdfName.names);
    if (names == null) {
      names = PdfDictionary();
      put(PdfName.names, names);
      final doc = pdfRepresentation().indirectHandle()?.getDocument();
      if (doc != null) {
        names.attachToDocument(doc);
      }
    }
    names.put(PdfName.dests, treeDict);
    names.markChanged();
  }

  /// Adds a name to a NameTree.
  Future<void> addNameToNameTree(
      PdfString key, PdfObject value, PdfName treeName) async {
    final tree = await PdfNameTree.create(this, treeName);
    tree.addEntry(key, value);
    final treeDict = tree.buildTree();

    PdfDictionary? names =
        await pdfRepresentation().dictionaryEntry(PdfName.names);
    if (names == null) {
      names = PdfDictionary();
      put(PdfName.names, names);
      final doc = pdfRepresentation().indirectHandle()?.getDocument();
      if (doc != null) {
        names.attachToDocument(doc);
      }
    }
    names.put(treeName, treeDict);
    names.markChanged();
  }

  /// Gets the metadata stream from the catalog.
  Future<PdfStream?> getMetadata() async {
    return await pdfRepresentation().streamEntry(PdfName.metadata);
  }

  /// Sets the metadata stream for the document.
  PdfCatalog setMetadata(PdfStream metadata) {
    put(PdfName.metadata, metadata);
    return this;
  }

  /// Gets the OutputIntents array.
  Future<PdfArray?> getOutputIntents() async {
    return await pdfRepresentation().arrayEntry(PdfName.outputIntents);
  }

  /// Adds an output intent to the document.
  PdfCatalog registerOutputProfile(PdfObject outputIntent) {
    PdfArray? intents =
        pdfRepresentation().getMap()?[PdfName.outputIntents] as PdfArray?;
    if (intents == null) {
      intents = PdfArray();
      final doc = pdfRepresentation().indirectHandle()?.getDocument();
      if (doc != null) {
        intents.attachToDocument(doc);
      }
      put(PdfName.outputIntents, intents);
    }
    intents.add(outputIntent);
    intents.markChanged();
    return this;
  }

  // =====================================================================
  // ISO 32000-1:2008, 7.7.2, Table 28 - entries in the catalog dictionary.
  // =====================================================================

  /// `/Version`.
  static final PdfName versionKey = PdfName.intern('Version');

  /// `/Extensions`.
  static final PdfName extensionsKey = PdfName.intern('Extensions');

  /// `/PageLabels`.
  static final PdfName pageLabelsKey = PdfName.intern('PageLabels');

  /// `/OpenAction`.
  static final PdfName openActionKey = PdfName.intern('OpenAction');

  /// `/AA`, the document level additional-actions dictionary.
  static final PdfName additionalActionsKey = PdfName.intern('AA');

  /// `/URI`.
  static final PdfName uriKey = PdfName.intern('URI');

  /// `/AcroForm`.
  static final PdfName acroFormKey = PdfName.intern('AcroForm');

  /// `/MarkInfo`.
  static final PdfName markInfoKey = PdfName.intern('MarkInfo');

  /// `/Lang`.
  static final PdfName langKey = PdfName.intern('Lang');

  /// `/SpiderInfo`.
  static final PdfName spiderInfoKey = PdfName.intern('SpiderInfo');

  /// `/OCProperties`.
  static final PdfName ocPropertiesKey = PdfName.intern('OCProperties');

  /// `/Perms`.
  static final PdfName permsKey = PdfName.intern('Perms');

  /// `/Legal`.
  static final PdfName legalKey = PdfName.intern('Legal');

  /// `/Collection`.
  static final PdfName collectionKey = PdfName.intern('Collection');

  /// `/NeedsRendering`.
  static final PdfName needsRenderingKey = PdfName.intern('NeedsRendering');

  /// Sets `/Version` (PDF 1.4), the version the document conforms to when it
  /// is later than the one in the file header. Table 28 requires a name
  /// object, so `/1.7` and not `1.7`.
  PdfCatalog setVersion(PdfVersion version) {
    put(versionKey, version.toPdfName());
    return this;
  }

  /// Gets `/Version`, or `null` when the entry is absent or unparsable. The
  /// document then conforms to the version given in the file header.
  Future<PdfVersion?> getVersion() async {
    final name = await pdfRepresentation().nameEntry(versionKey);
    if (name == null) return null;
    try {
      return PdfVersion.fromPdfName(name);
    } on ArgumentError {
      return null;
    }
  }

  /// Sets `/Extensions`, the developer extensions dictionary of 7.12.
  PdfCatalog setExtensions(PdfDictionary extensions) {
    put(extensionsKey, extensions);
    return this;
  }

  /// Gets `/Extensions`, or `null` when absent.
  Future<PdfDictionary?> getExtensions() =>
      pdfRepresentation().dictionaryEntry(extensionsKey);

  /// Sets `/PageLabels` (PDF 1.3), the number tree defining the page labels.
  PdfCatalog setPageLabels(PdfDictionary numberTree) {
    put(pageLabelsKey, numberTree);
    return this;
  }

  /// Gets `/PageLabels`, or `null` when absent.
  Future<PdfDictionary?> getPageLabels() =>
      pdfRepresentation().dictionaryEntry(pageLabelsKey);

  /// Gets `/Names` (PDF 1.2), the document's name dictionary, or `null`.
  Future<PdfDictionary?> getNames() =>
      pdfRepresentation().dictionaryEntry(PdfName.names);

  /// Gets `/Dests` (PDF 1.1), the catalog level named destinations dictionary,
  /// or `null` when absent.
  Future<PdfDictionary?> getDests() =>
      pdfRepresentation().dictionaryEntry(PdfName.dests);

  /// Sets `/PageLayout` from the Table 28 vocabulary.
  PdfCatalog setPageLayoutMode(PdfPageLayout layout) {
    put(PdfName.pageLayout, layout.toPdfName());
    return this;
  }

  /// Gets `/PageLayout`, defaulting to [PdfPageLayout.singlePage] as Table 28
  /// prescribes when the entry is absent or unrecognized.
  Future<PdfPageLayout> getPageLayoutMode() async {
    return PdfPageLayout.fromPdfName(
            await pdfRepresentation().nameEntry(PdfName.pageLayout)) ??
        PdfPageLayout.singlePage;
  }

  /// Sets `/PageMode` from the Table 28 vocabulary.
  PdfCatalog setPageModeValue(PdfPageMode mode) {
    put(PdfName.pageMode, mode.toPdfName());
    return this;
  }

  /// Gets `/PageMode`, defaulting to [PdfPageMode.useNone] as Table 28
  /// prescribes when the entry is absent or unrecognized.
  Future<PdfPageMode> getPageModeValue() async {
    return PdfPageMode.fromPdfName(
            await pdfRepresentation().nameEntry(PdfName.pageMode)) ??
        PdfPageMode.useNone;
  }

  /// Sets `/OpenAction` (PDF 1.1). Table 28 allows either an array defining a
  /// destination (12.3.2) or an action dictionary (12.6); anything else is
  /// rejected.
  PdfCatalog setOpenAction(PdfObject destinationOrAction) {
    if (destinationOrAction is! PdfArray &&
        destinationOrAction is! PdfDictionary) {
      throw PdfException(
          '/OpenAction shall be a destination array or an action dictionary.');
    }
    put(openActionKey, destinationOrAction);
    return this;
  }

  /// Gets `/OpenAction`, resolved through any indirect reference, or `null`.
  Future<PdfObject?> getOpenAction() =>
      pdfRepresentation().get(openActionKey, true);

  /// Removes `/OpenAction`, so the document opens at the top of the first page
  /// at the default magnification.
  PdfCatalog removeOpenAction() {
    pdfRepresentation().remove(openActionKey);
    markChanged();
    return this;
  }

  /// Sets `/AA` (PDF 1.4), the document level additional-actions dictionary.
  PdfCatalog setAdditionalActions(PdfDictionary additionalActions) {
    put(additionalActionsKey, additionalActions);
    return this;
  }

  /// Gets `/AA`, or `null` when absent.
  Future<PdfDictionary?> getAdditionalActions() =>
      pdfRepresentation().dictionaryEntry(additionalActionsKey);

  /// Gets `/URI` (PDF 1.1), the document level URI dictionary, or `null`.
  Future<PdfUriDictionary?> getUriDictionary() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(uriKey);
    return dictionary == null ? null : PdfUriDictionary(dictionary);
  }

  /// Gets `/URI`, creating and installing an empty dictionary when absent.
  Future<PdfUriDictionary> uriDictionary() async {
    final existing = await getUriDictionary();
    if (existing != null) return existing;
    final created = PdfUriDictionary();
    put(uriKey, created.pdfRepresentation());
    return created;
  }

  /// Gets `/AcroForm` (PDF 1.2), the interactive form dictionary, or `null`.
  Future<PdfDictionary?> getAcroForm() =>
      pdfRepresentation().dictionaryEntry(acroFormKey);

  /// Gets `/StructTreeRoot` (PDF 1.3), or `null` when the document is not
  /// tagged.
  Future<PdfDictionary?> getStructTreeRoot() =>
      pdfRepresentation().dictionaryEntry(PdfName.structTreeRoot);

  /// Gets `/MarkInfo` (PDF 1.4), or `null` when absent.
  Future<PdfMarkInfo?> getMarkInfo() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(markInfoKey);
    return dictionary == null ? null : PdfMarkInfo(dictionary);
  }

  /// Gets `/MarkInfo`, creating and installing an empty dictionary when the
  /// catalog has none yet.
  Future<PdfMarkInfo> markInfo() async {
    final existing = await getMarkInfo();
    if (existing != null) return existing;
    final created = PdfMarkInfo();
    put(markInfoKey, created.pdfRepresentation());
    return created;
  }

  /// Sets `/Lang` (PDF 1.4), the natural language of all text in the document
  /// (14.9.2). An empty identifier means the language is unknown, which
  /// Table 28 expresses by omitting the entry instead.
  PdfCatalog setLanguage(String language) {
    if (language.isEmpty) {
      throw PdfException(
          '/Lang shall not be empty; omit the entry to leave the language '
          'unknown.');
    }
    put(langKey, PdfString(language));
    return this;
  }

  /// Gets `/Lang`, or `null` when the language is unknown.
  Future<String?> getLanguage() async {
    return (await pdfRepresentation().stringEntry(langKey))
        ?.decodeMappingText();
  }

  /// Sets `/SpiderInfo` (PDF 1.3), the Web Capture information dictionary.
  PdfCatalog setSpiderInfo(PdfDictionary spiderInfo) {
    put(spiderInfoKey, spiderInfo);
    return this;
  }

  /// Gets `/SpiderInfo`, or `null` when absent.
  Future<PdfDictionary?> getSpiderInfo() =>
      pdfRepresentation().dictionaryEntry(spiderInfoKey);

  /// Sets `/OCProperties` (PDF 1.5), the optional content properties
  /// dictionary. Table 28 requires it when the document contains optional
  /// content.
  PdfCatalog setOcProperties(PdfDictionary ocProperties) {
    put(ocPropertiesKey, ocProperties);
    return this;
  }

  /// Gets `/OCProperties`, or `null` when absent.
  Future<PdfDictionary?> getOcProperties() =>
      pdfRepresentation().dictionaryEntry(ocPropertiesKey);

  /// Sets `/Perms` (PDF 1.5), the permissions dictionary of 12.8.4, Table 258.
  PdfCatalog setPermissions(PdfDictionary permissions) {
    put(permsKey, permissions);
    return this;
  }

  /// Gets `/Perms`, or `null` when absent.
  Future<PdfDictionary?> getPermissions() =>
      pdfRepresentation().dictionaryEntry(permsKey);

  /// Gets `/Legal` (PDF 1.5), the legal attestation dictionary of 12.8.5,
  /// or `null` when absent.
  Future<PdfLegalAttestation?> getLegalAttestation() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(legalKey);
    return dictionary == null ? null : PdfLegalAttestation(dictionary);
  }

  /// Gets `/Legal`, creating and installing an empty dictionary when absent.
  Future<PdfLegalAttestation> legalAttestation() async {
    final existing = await getLegalAttestation();
    if (existing != null) return existing;
    final created = PdfLegalAttestation();
    put(legalKey, created.pdfRepresentation());
    return created;
  }

  /// Sets `/Collection` (PDF 1.7), the collection dictionary used to present
  /// file attachments (12.3.5).
  PdfCatalog setCollection(PdfDictionary collection) {
    put(collectionKey, collection);
    return this;
  }

  /// Gets `/Collection`, or `null` when absent.
  Future<PdfDictionary?> getCollection() =>
      pdfRepresentation().dictionaryEntry(collectionKey);

  /// Sets `/NeedsRendering` (PDF 1.7), the XFA flag telling a reader whether
  /// the document shall be regenerated when first opened. Default `false`.
  PdfCatalog setNeedsRendering(bool value) {
    put(needsRenderingKey, PdfBoolean(value));
    return this;
  }

  /// Gets `/NeedsRendering`, defaulting to `false`.
  Future<bool> getNeedsRendering() async {
    return (await pdfRepresentation().booleanEntry(needsRenderingKey))
            ?.getValue() ??
        false;
  }

  /// Gets `/PieceInfo` (PDF 1.4), the private data conforming products keep
  /// for the document as a whole (14.5, Table 318), or `null` when absent.
  Future<PdfPagePiece?> getPieceInfo() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfPagePiece.pieceInfo);
    return dictionary == null ? null : PdfPagePiece(dictionary);
  }

  /// Gets `/PieceInfo`, creating and installing an empty page-piece dictionary
  /// when the catalog has none yet.
  Future<PdfPagePiece> pieceInfo() async {
    final existing = await getPieceInfo();
    if (existing != null) return existing;
    final created = PdfPagePiece();
    put(PdfPagePiece.pieceInfo, created.pdfRepresentation());
    return created;
  }

  /// Adds [requirement] to `/Requirements` (PDF 1.7), the array of what a
  /// conforming reader shall provide for the document to work (12.10).
  Future<PdfCatalog> addRequirement(PdfRequirement requirement) async {
    await requirement.validate();
    var requirements =
        await pdfRepresentation().arrayEntry(PdfRequirement.requirementsKey);
    if (requirements == null) {
      requirements = PdfArray();
      put(PdfRequirement.requirementsKey, requirements);
    }
    requirements.add(requirement.pdfRepresentation());
    requirements.markChanged();
    markChanged();
    return this;
  }

  /// Gets `/Requirements`, or `null` when the document states none.
  Future<PdfArray?> getRequirements() =>
      pdfRepresentation().arrayEntry(PdfRequirement.requirementsKey);

  /// Gets the document requirements, in the order of `/Requirements`.
  Future<List<PdfRequirement>> getDocumentRequirements() async {
    final requirements = await getRequirements();
    if (requirements == null) return const [];
    final result = <PdfRequirement>[];
    for (var index = 0; index < requirements.size(); index++) {
      final entry = await requirements.dictionaryEntry(index);
      if (entry != null) result.add(PdfRequirement(entry));
    }
    return result;
  }

  /// `/Threads`.
  static final PdfName threadsKey = PdfName.intern('Threads');

  /// Adds [thread] to `/Threads` (PDF 1.1), the array of the document's
  /// article threads (12.4.3). The array is created on first use and is kept
  /// indirect, as Table 28 requires.
  Future<PdfCatalog> addArticleThread(PdfArticleThread thread) async {
    var threads = await pdfRepresentation().arrayEntry(threadsKey);
    if (threads == null) {
      threads = PdfArray();
      final doc = pdfRepresentation().indirectHandle()?.getDocument();
      if (doc != null) {
        threads.attachToDocument(doc);
      }
      put(threadsKey, threads);
    }
    threads.add(thread.reference());
    threads.markChanged();
    markChanged();
    return this;
  }

  /// Gets `/Threads`, or `null` when the document defines no articles.
  Future<PdfArray?> getThreads() => pdfRepresentation().arrayEntry(threadsKey);

  /// Gets the document's article threads, in the order of `/Threads`.
  Future<List<PdfArticleThread>> getArticleThreads() async {
    final threads = await getThreads();
    if (threads == null) return const [];
    final result = <PdfArticleThread>[];
    for (var index = 0; index < threads.size(); index++) {
      final entry = await threads.dictionaryEntry(index);
      if (entry != null) result.add(PdfArticleThread(entry));
    }
    return result;
  }

  void put(PdfName key, PdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
  }
}

class _OutlineProcessingItem {
  final PdfDictionary dictionary;
  final PdfOutline parent;
  _OutlineProcessingItem(this.dictionary, this.parent);
}
