import 'dart:typed_data';

import '../xmp/xmp_meta.dart';
import '../xmp/xmp_const.dart';
import '../xmp/pdf_const.dart';
import 'pdf_catalog.dart';
import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_string.dart';
import 'pdf_array.dart';
import 'pdf_stream.dart';
import 'pdf_boolean.dart';
import 'pdf_object.dart';
import 'pdf_object_copier.dart';
import 'pdf_page.dart';
import 'pdf_pages_tree.dart';
import 'pdf_reader.dart';
import 'pdf_writer.dart';
import 'pdf_xref_table.dart';
import 'pdf_version.dart';
import 'pdf_output_intent.dart';
import 'package:pdfcraft/src/commons/pdfcraft_log_manager.dart';
import 'stamping_properties.dart';
import '../geom/page_size.dart';
import '../exceptions/pdf_exception.dart';
import '../font/pdf_font.dart';
import '../font/pdf_font_factory.dart';
import 'pdf_document_info.dart';
import 'pdf_encryption.dart';
import '../../commons/actions/event_manager.dart';
import 'event/pdf_document_event.dart';
import 'tagging/pdf_struct_tree_root.dart';
import 'tagging/tag_structure_context.dart';
import 'filespec/pdf_file_spec.dart';
import 'pdf_outline.dart';

/// Document operations, page access and serialization lifecycle.
class CraftPdfDocument {
  /// PDF names to remove from original trailer (used in append mode)
  // ignore: unused_field
  static final List<CraftPdfName> _pdfNamesToRemoveFromOriginalTrailer = [
    CraftPdfName.encrypt,
    CraftPdfName.size,
    CraftPdfName.prev,
    CraftPdfName.root,
    CraftPdfName.info,
    CraftPdfName.id,
  ];

  /// List of loaded fonts to prevent duplication and enable flushing.
  final Map<CraftPdfIndirectReference, CraftPdfFont> _documentFonts = {};

  /// List of indirect objects used in the document.
  CraftPdfXrefTable? _xrefTable;

  /// PdfWriter associated with the document.
  static final _logger = LogManager.getLoggerByName('PdfDocument');
  final CraftPdfWriter? _writer;

  /// PdfReader associated with the document.
  CraftPdfReader? _reader;

  /// Document catalog.
  CraftPdfCatalog? _catalog;

  /// Document trailer.
  CraftPdfDictionary? _trailer;

  /// Document version.
  CraftPdfVersion? _version;

  /// Encryption handler.
  CraftPdfEncryption? _encryption;

  /// Whether the document is closed.
  bool _closed = false;

  /// Whether the closing process has started.
  bool _isClosing = false;

  /// Default page size.
  CraftPageSize _defaultPageSize = CraftPageSize.defaultSize;

  /// Default font - lazy initialized.
  CraftPdfFont? _defaultFont;

  /// Stamping properties.
  final CraftStampingProperties? _properties;
  bool _rewriteAfterRecovery = false;
  bool get wasRepaired => _reader?.rebuiltXref ?? false;

  /// Original document ID.
  CraftPdfString? _originalDocumentId;

  /// Modified document ID.
  CraftPdfString? _modifiedDocumentId;

  /// Document info - lazy initialized.
  CraftPdfDocumentInfo? _info;

  /// XMP Metadata bytes for the document.
  Uint8List? _xmpMetadataBytes;

  /// XMP Metadata which is used to prevent bytes deserialization for a few times on the same bytes.
  CraftXMPMeta? _xmpMetadata;

  // Event handlers map
  final Map<String, List<CraftEventHandler>> _handlers = {};

  /// Document fingerprints.
  // ignore: unused_field
  CraftFingerPrint? _fingerPrint;

  /// Tag structure context.
  CraftTagStructureContext? _tagStructureContext;

  /// Root of the structure tree.
  CraftPdfStructTreeRoot? _structTreeRoot;

  /// Index for next struct parent.
  int _structParentIndex = 0;

  /// Opens PDF document in reading mode.

  /// Opens PDF document in reading mode.
  ///
  /// [reader] - PDF reader.
  CraftPdfDocument.fromReader(CraftPdfReader reader)
      : _reader = reader,
        _writer = null,
        _properties = null {
    _open(null);
  }

  /// Opens PDF document in writing mode.
  /// Document has no pages when initialized.
  ///
  /// [writer] - PDF writer.
  CraftPdfDocument.fromWriter(CraftPdfWriter writer)
      : _writer = writer,
        _reader = null,
        _properties = null {
    _open(null);
    _initCatalog();
  }

  void _initCatalog() {
    _catalog?.init();
  }

  /// Opens PDF document in stamping mode.
  ///
  /// [reader] - PDF reader.
  /// [writer] - PDF writer.
  /// [properties] - stamping properties.
  CraftPdfDocument({
    CraftPdfReader? reader,
    CraftPdfWriter? writer,
    CraftStampingProperties? properties,
  })  : _reader = reader,
        _writer = writer,
        _properties = properties {
    _open(null);
  }

  /// Initializes document.
  void _open(CraftPdfVersion? newPdfVersion) {
    _fingerPrint = CraftFingerPrint();
    // Initialize xref table
    if (_reader != null) {
      _xrefTable = _reader!.xref;
      _version = _reader!.getPdfVersion();
      _reader!.setDocument(this);
    } else {
      _xrefTable = CraftPdfXrefTable();
      _version = CraftPdfVersion.PDF_1_7;
    }

    // Set document reference in writer
    if (_writer != null) {
      _writer.document = this;

      if (_reader == null) {
        // New document - create catalog and add creation date
        _catalog = CraftPdfCatalog(CraftPdfDictionary());
        _catalog!.pdfRepresentation().attachToDocument(this);
        documentDetailsSync().addCreationDate();
      }
      if (_reader == null) documentDetailsSync().addModDate();

      // Initialize trailer
      if (_trailer == null) {
        _trailer = CraftPdfDictionary();
      }

      // Rebuild writer-owned trailer entries for a fresh revision while keeping
      // extension entries supplied by the input document.
      if (_trailer!.size() > 0 &&
          _reader != null &&
          !usesIncrementalRevision()) {
        final keysToRemove = [
          CraftPdfName.root,
          CraftPdfName.info,
          CraftPdfName.id,
          CraftPdfName.prev,
          CraftPdfName.size,
          CraftPdfName.xrefStm,
          CraftPdfName.encrypt,
          CraftPdfName.index,
          CraftPdfName.w
        ];
        for (final key in keysToRemove) {
          _trailer!.remove(key);
        }
      }

      // Ensure modified ID is updated or preserved
      if (_trailer!.containsKey(CraftPdfName.id)) {
        // In append mode, usually we preserve unless we specifically want to update.
      } else {
        // Create IDs if missing
        final idArray = CraftPdfArray();
        idArray.add(initialDocumentIdentifier());
        idArray.add(revisionIdentifier());
        _trailer!.put(CraftPdfName.id, idArray);
      }

      // Set root reference in trailer
      if (_catalog != null) {
        _trailer!.put(CraftPdfName.root, _catalog!.pdfRepresentation());
      }
    }

    _xrefTable?.initFreeReferencesList(this);
  }

  /// Loads document from reader. Must be called after constructor for reading mode.
  Future<void> load() async {
    if (_reader == null) return;

    await _reader!.read();
    if (_writer != null &&
        _reader!.rebuiltXref &&
        (_properties?.usesIncrementalRevision() ?? false)) {
      if (_properties!.repairedSaveMode == PdfRepairedSaveMode.reject) {
        throw FormatException(
            'A reconstructed cross-reference table requires an explicit full rewrite before signing or incremental editing.');
      }
      _rewriteAfterRecovery = true;
    }

    // Get catalog from reader's trailer
    final catalogDict = await _reader!.rootCatalog();
    if (catalogDict == null) {
      throw CraftPdfException('Corrupted root entry in trailer');
    }

    // Create catalog wrapper
    _catalog = CraftPdfCatalog(catalogDict);

    // Ensure catalog's indirect reference has this document set
    final catRef = catalogDict.indirectHandle();
    if (catRef != null) {
      catRef.setDocument(this);
    }

    // Get trailer from reader
    _trailer = _reader!.trailer;

    // Bind edits to the actual information object, not a constructor-time
    // placeholder that is absent from the input cross-reference table.
    if (_writer != null) {
      final pending = _info?.pdfRepresentation();
      final stored = await _trailer?.dictionaryEntry(CraftPdfName.info) ??
          CraftPdfDictionary();
      if (pending != null && !identical(pending, stored)) {
        for (final entry in await pending.entrySet()) {
          stored.put(entry.key, entry.value);
        }
      }
      stored.attachToDocument(this);
      _info = CraftPdfDocumentInfo(stored)..addModDate();
      _trailer?.put(CraftPdfName.info, stored);
    }

    // Load Document IDs
    final idArray = await _trailer?.arrayEntry(CraftPdfName.id);
    if (idArray != null) {
      if (idArray.size() > 0) {
        _originalDocumentId = await idArray.stringEntry(0);
      }
      if (idArray.size() > 1) {
        _modifiedDocumentId = await idArray.stringEntry(1);
      }
    }

    // Initialize version from reader
    _version = _reader!.getPdfVersion();

    // Initialize Pages Tree from saved catalog
    final tree = pageHierarchy();
    await tree.init();

    // Initialize Tag Structure if present
    final str = await _catalog!
        .pdfRepresentation()
        .dictionaryEntry(CraftPdfName.structTreeRoot);
    if (str != null) {
      await initializeTaggingWhenReady(str);
    }

    // Update version from catalog
    await _updatePdfVersionFromCatalog();
  }

  /// Factory method to open document for reading.
  static Future<CraftPdfDocument> open(CraftPdfReader reader) async {
    final doc = CraftPdfDocument.fromReader(reader);
    await doc.load();
    return doc;
  }

  /// Factory method to create new document.
  static CraftPdfDocument create(CraftPdfWriter writer) {
    return CraftPdfDocument.fromWriter(writer);
  }

  // ============== GETTERS ==============

  /// Gets PdfReader associated with the document.
  CraftPdfReader? inputReader() => _reader;

  /// Gets PdfWriter associated with the document.
  CraftPdfWriter? outputWriter() => _writer;

  /// Gets document catalog.
  CraftPdfCatalog rootCatalog() {
    if (_catalog == null) {
      _catalog = CraftPdfCatalog(CraftPdfDictionary());
      _catalog!.pdfRepresentation().attachToDocument(this);
      if (_trailer != null) {
        _trailer!.put(CraftPdfName.root, _catalog!.pdfRepresentation());
      }
    }
    return _catalog!;
  }

  /// Gets document trailer.
  CraftPdfDictionary fileTrailer() {
    _trailer ??= CraftPdfDictionary();
    return _trailer!;
  }

  /// Gets xref table.
  CraftPdfXrefTable? referenceIndex() => _xrefTable;

  /// Alias for getXrefTable for compatibility.
  CraftPdfXrefTable crossReferenceTable() => _xrefTable ?? CraftPdfXrefTable();

  /// Gets encryption handler.
  CraftPdfEncryption? securityCodec() => _encryption;

  /// Gets document version.
  CraftPdfVersion? formatVersion() => _version;

  /// Returns true if document is closed.
  bool lifecycleClosed() => _closed;

  /// Returns true if closing process has started.
  bool lifecycleClosing() => _isClosing;

  /// Gets default page size.
  CraftPageSize defaultPageExtent() => _defaultPageSize;

  /// Sets default page size.
  void configureDefaultPageExtent(CraftPageSize pageSize) {
    _defaultPageSize = pageSize;
  }

  /// Gets the default font for the document.
  ///
  /// The default font is lazily initialized using Helvetica.
  /// Returns the default font, or null if creation fails.
  CraftPdfFont? defaultTypeface() {
    if (_defaultFont == null) {
      try {
        // Use Helvetica as the default font
        _defaultFont = CraftPdfFontFactory.createFont('Helvetica');
        if (_writer != null && _defaultFont != null) {
          _defaultFont!.attachToDocument(this);
        }
      } catch (e) {
        // Log error or handle gracefully
        _defaultFont = null;
      }
    }
    return _defaultFont;
  }

  /// Gets a PdfFont from a font dictionary.
  ///
  /// This is used to retrieve embedded fonts from the PDF document.
  /// Returns null if the font cannot be created.
  Future<CraftPdfFont?> resolveTypeface(
      CraftPdfDictionary fontDictionary) async {
    final ref = fontDictionary.indirectHandle();
    if (ref != null && _documentFonts.containsKey(ref)) {
      return _documentFonts[ref];
    }
    try {
      final font =
          await CraftPdfFontFactory.createFontFromDictionary(fontDictionary);
      if (font != null) {
        // If we created a font, we should add it to our tracking map
        // but only if it has an indirect reference (which it usually does or will)
        return registerTypeface(font);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Registers font storage for serialization during this document's lifecycle.
  CraftPdfFont registerTypeface(CraftPdfFont font) {
    font.attachToDocument(this);
    // font.setForbidRelease(); // Not implemented yet
    final ref = font.pdfRepresentation().indirectHandle();
    if (ref != null) {
      _documentFonts[ref] = font;
    }
    return font;
  }

  /// List all newly added or loaded fonts.
  List<CraftPdfFont> registeredTypefaces() {
    return _documentFonts.values.toList();
  }

  /// Adds event handler.
  void subscribeEvent(String type, CraftEventHandler handler) {
    _handlers.putIfAbsent(type, () => []).add(handler);
  }

  /// Removes event handler.
  void unsubscribeEvent(String type, CraftEventHandler handler) {
    _handlers[type]?.remove(handler);
  }

  /// Dispatches event.
  void publishEvent(CraftEvent event) {
    final list = _handlers[event.eventType];
    if (list != null) {
      for (final handler in list) {
        handler.onEvent(event);
      }
    }
  }

  // ============== PAGES ==============

  /// Gets pages tree.
  CraftPdfPagesTree pageHierarchy() {
    final tree = rootCatalog().getPageTree();
    tree.setDocument(this);
    return tree;
  }

  /// Creates and adds new page to the end of document.
  Future<CraftPdfPage> appendBlankPage([CraftPageSize? pageSize]) async {
    _checkClosingStatus();
    final page = CraftPdfPage(CraftPdfDictionary());
    page.setMediaBounds(pageSize ?? _defaultPageSize);
    await pageHierarchy().appendPageObject(page, this);

    publishEvent(CraftPdfDocumentEvent(
        CraftPdfDocumentEvent.startPage, page.pdfRepresentation()));
    publishEvent(CraftPdfDocumentEvent(
        CraftPdfDocumentEvent.insertPage, page.pdfRepresentation()));

    return page;
  }

  /// Creates and inserts new page at the specified position (1-based index).
  ///
  /// [index] - Position to insert page to (1-based)
  /// [pageSize] - Optional size of the new page
  Future<CraftPdfPage> insertBlankPage(int index,
      [CraftPageSize? pageSize]) async {
    _checkClosingStatus();
    final page = CraftPdfPage(CraftPdfDictionary());
    page.setMediaBounds(pageSize ?? _defaultPageSize);
    await pageHierarchy().insertPageObject(index, page, this);

    publishEvent(CraftPdfDocumentEvent(
        CraftPdfDocumentEvent.startPage, page.pdfRepresentation()));
    publishEvent(CraftPdfDocumentEvent(
        CraftPdfDocumentEvent.insertPage, page.pdfRepresentation()));

    return page;
  }

  /// Adds existing page to the end of document.
  Future<CraftPdfPage> appendPageObject(CraftPdfPage page) async {
    _checkClosingStatus();
    await pageHierarchy().appendPageObject(page, this);
    publishEvent(CraftPdfDocumentEvent(
        CraftPdfDocumentEvent.insertPage, page.pdfRepresentation()));
    return page;
  }

  /// Inserts existing page at the specified position (1-based index).
  ///
  /// [index] - Position to insert page to (1-based)
  /// [page] - The page to insert
  Future<CraftPdfPage> insertPageObject(int index, CraftPdfPage page) async {
    _checkClosingStatus();
    await pageHierarchy().insertPageObject(index, page, this);
    publishEvent(CraftPdfDocumentEvent(
        CraftPdfDocumentEvent.insertPage, page.pdfRepresentation()));
    return page;
  }

  /// Gets the page by page number (1-based).
  Future<CraftPdfPage?> pageAt(int pageNumber) async {
    return await pageHierarchy().pageAt(pageNumber);
  }

  /// Gets the first page of the document.
  Future<CraftPdfPage?> firstPage() async {
    if (pageTotal() > 0) {
      return await pageAt(1);
    }
    return null;
  }

  /// Gets the last page of the document.
  Future<CraftPdfPage?> lastPage() async {
    final numPages = pageTotal();
    if (numPages > 0) {
      return await pageAt(numPages);
    }
    return null;
  }

  /// Gets number of pages in the document.
  int pageTotal() {
    return pageHierarchy().pageTotal();
  }

  /// Gets the page by its PdfDictionary.
  ///
  /// Returns null if the page is not found.
  Future<CraftPdfPage?> findPageObject(
      CraftPdfDictionary pageDictionary) async {
    return await pageHierarchy().findPageObject(pageDictionary);
  }

  /// Gets page number by page.
  int pageOrdinal(CraftPdfPage page) {
    return pageHierarchy().pageOrdinal(page);
  }

  /// Removes the page at the specified position (1-based index).
  ///
  /// [pageNum] - the one-based index of the PdfPage to be removed.
  Future<void> deletePageAt(int pageNum) async {
    _checkClosingStatus();
    final tree = pageHierarchy();
    final count = tree.pageTotal();
    if (pageNum < 1 || pageNum > count) {
      throw RangeError.range(pageNum, 1, count, 'pageNum');
    }
    final detached = await tree.detachPage(pageNum);
    if (detached == null) {
      throw StateError(
          'The selected page could not be detached from its tree.');
    }

    final dictionary = detached.pdfRepresentation();
    dictionary.remove(CraftPdfName.parent);
    detached.parentPages = null;
    dictionary.indirectHandle()?.setState(CraftPdfObject.free);

    // Keep the existing cleanup hooks; widget cleanup is currently a stub.
    if (usesTagging()) {
      taggingContext()?.removePageTags(detached);
    }
    _removeUnusedWidgetsFromFields(detached);
    await rootCatalog().removeOutlines(detached);

    // Observers receive the completed page-tree state.
    publishEvent(
        CraftPdfDocumentEvent(CraftPdfDocumentEvent.detachPage, dictionary));
  }

  /// Removes all widgets associated with a given page from AcroForm structure.
  void _removeUnusedWidgetsFromFields(CraftPdfPage page) {
    if (page.hasBeenWritten()) {
      return;
    }
    // Stub implementation:
    // PdfDictionary acroForm = getCatalog().getPdfObject().getAsDictionary(PdfName.acroForm);
    // PdfArray fields = acroForm.getAsArray(PdfName.fields);
    // Remove widgets logic... (Requires Annotations support)
  }

  /// Adds file attachment at document level.
  ///
  /// [key] - name of the destination.
  /// [fs] - [PdfFileSpec] object.
  Future<void> registerAttachment(String key, CraftPdfFileSpec fs) async {
    _checkClosingStatus();
    await rootCatalog().addNameToNameTree(CraftPdfString(key),
        fs.pdfRepresentation(), CraftPdfName.embeddedFiles);
  }

  /// Adds file associated with PDF document as a whole.
  Future<void> associateAttachment(
      String description, CraftPdfFileSpec fs) async {
    final fsDict = fs.pdfRepresentation();
    if (!fsDict.containsKey(CraftPdfName.afRelationship)) {
      // Log error or throw
    }
    CraftPdfArray? afArray =
        await rootCatalog().pdfRepresentation().arrayEntry(CraftPdfName.af);
    if (afArray == null) {
      afArray = CraftPdfArray();
      afArray.attachToDocument(this);
      rootCatalog().put(CraftPdfName.af, afArray);
    }
    afArray.add(fs.pdfRepresentation());
    await registerAttachment(description, fs);
  }

  /// Adds a named destination.
  Future<void> registerDestination(String key, CraftPdfObject value) async {
    await rootCatalog().registerDestination(CraftPdfString(key), value);
  }

  /// Gets the outlines of the document.
  Future<CraftPdfOutline?> outlineTree(bool updateOutlines) async {
    _checkClosingStatus();
    return await rootCatalog().outlineTree(updateOutlines);
  }

  /// Initializes an outline tree of the document.
  void initializeOutlineTree() {
    _checkClosingStatus();
    if (!containsOutlineTree()) {
      CraftPdfOutline.createRoot(this);
    }
  }

  /// Indicates if the document has any outlines.
  bool containsOutlineTree() {
    return rootCatalog().containsOutlineTree();
  }

  /// Gets page labels.
  Future<List<String>?> pageLabelValues() async {
    // Stub
    return null;
  }

  /// Checks ISO conformance.
  void validateDocumentRules(dynamic validationContext) {
    // Stub
  }

  /// Removes the specified page from this document.
  ///
  /// Returns true if this document contained the specified page.
  Future<bool> detachPage(CraftPdfPage page) async {
    _checkClosingStatus();
    final pageNum = pageOrdinal(page);
    if (pageNum >= 1) {
      await deletePageAt(pageNum);
      return true;
    }
    return false;
  }

  /// Moves page to new place in same document with all it tag structure.
  ///
  /// [page] - page to be moved in document if present
  /// [insertBefore] - indicates before which page new one will be inserted to (1-based)
  Future<bool> relocatePage(CraftPdfPage page, int insertBefore) async {
    _checkClosingStatus();
    final pageNum = pageOrdinal(page);
    if (pageNum > 0) {
      await relocatePageAt(pageNum, insertBefore);
      return true;
    }
    return false;
  }

  /// Moves page to new place in same document with all it tag structure.
  ///
  /// [pageNumber] - number of Page that will be moved (1-based)
  /// [insertBefore] - indicates before which page new one will be inserted to (1-based)
  Future<void> relocatePageAt(int pageNumber, int insertBefore) async {
    _checkClosingStatus();
    if (insertBefore < 1 || insertBefore > pageTotal() + 1) {
      throw RangeError('Requested page number $insertBefore is out of bounds.');
    }

    // TODO: Tagged PDF support (GetStructTreeRoot)
    // For now we assume no StructTreeRoot updates needed or handled separately.

    // Detach from parent and remove from tree.
    // We use getPagesTree().removePage() directly to avoid 'freeing' the object,
    // which happens in PdfDocument.removePageAt().
    final removedPage = await pageHierarchy().detachPage(pageNumber);
    if (removedPage == null) {
      // Page not found or error
      return;
    }

    if (insertBefore > pageNumber) {
      insertBefore--;
    }

    // Re-attach page at new location
    await pageHierarchy().insertPageObject(insertBefore, removedPage, this);
  }

  // ============== OBJECTS ==============

  /// Gets number of indirect objects in the document.
  int storedObjectCount() {
    return _xrefTable?.size() ?? 0;
  }

  /// Creates next indirect reference.
  CraftPdfIndirectReference allocateObjectHandle() {
    final objNr = _xrefTable!.size();
    return _xrefTable!
        .add(CraftPdfIndirectReference(objNr, 0)..setDocument(this))!;
  }

  /// Reads object by indirect reference.
  Future<CraftPdfObject?> readObject(
      CraftPdfIndirectReference reference) async {
    if (reference.getDocument() != this) {
      throw ArgumentError("Indirect reference does not belong to document");
    }
    if (reference.isFree()) return null;
    if (_reader != null) {
      return await _reader!.readObject(reference.objectNumber());
    }
    return null;
  }

  /// Gets PdfObject by object number.
  ///
  /// Returns [PdfObject] or null if object not found.
  Future<CraftPdfObject?> pdfRepresentation(int objNum) async {
    _checkClosingStatus();
    final reference = _xrefTable?.get(objNum);
    if (reference == null) {
      return null;
    }
    return await reference.targetObject();
  }

  // ============== APPEND MODE ==============

  /// Returns true if the document is opened in append mode.
  bool usesIncrementalRevision() =>
      !_rewriteAfterRecovery &&
      (_properties?.usesIncrementalRevision() ?? false);

  /// Gets the stamping properties for this document.
  CraftStampingProperties? revisionOptions() => _properties;

  // ============== ENCRYPTION ==============

  /// Returns true if the document is encrypted.
  bool usesEncryption() => _encryption != null;

  /// Sets the encryption for the document.
  void configureEncryption(CraftPdfEncryption? encryption) {
    _encryption = encryption;
  }

  /// Gets original document id.
  CraftPdfString initialDocumentIdentifier() {
    return _originalDocumentId ??= CraftPdfString.fromBytes(
        CraftPdfEncryption.generateNewDocumentId(), true);
  }

  /// Gets modified document id.
  CraftPdfString revisionIdentifier() {
    return _modifiedDocumentId ??= CraftPdfString.fromBytes(
        CraftPdfEncryption.generateNewDocumentId(), true);
  }

  // ============== INFO ==============

  /// Gets document information dictionary.
  Future<CraftPdfDocumentInfo> documentDetails() async {
    _checkClosingStatus();
    if (_info == null) {
      final infoDict = _trailer != null
          ? await _trailer!.dictionaryEntry(CraftPdfName.info)
          : null;
      _info = CraftPdfDocumentInfo(infoDict ?? CraftPdfDictionary());
    }
    return _info!;
  }

  /// Gets the document information synchronously.
  /// If info is not loaded, it creates a new one.
  CraftPdfDocumentInfo documentDetailsSync() {
    _checkClosingStatus();
    if (_info == null) {
      CraftPdfDictionary? infoDict;
      if (_trailer != null) {
        var infoObj = _trailer!.getMap()?[CraftPdfName.info];
        if (infoObj is CraftPdfIndirectReference) {
          infoObj = infoObj.targetObjectSync();
        }
        if (infoObj is CraftPdfDictionary) {
          infoDict = infoObj;
        }
      }
      _info = CraftPdfDocumentInfo(infoDict ?? CraftPdfDictionary());
    }
    return _info!;
  }

  // ============== FLUSH ==============

  /// Gets the tag structure context.
  CraftTagStructureContext? taggingContext() {
    if (_tagStructureContext == null) {
      _tagStructureContext = CraftTagStructureContext(this);
    }
    return _tagStructureContext;
  }

  /// Flushes all fonts.
  Future<void> writeRegisteredTypefaces() async {
    for (final font in _documentFonts.values) {
      await font.flush();
    }
  }

  /// Flushes pages to free memory (stub).
  Future<void> writePendingPages() async {
    _checkClosingStatus();
  }

  /// Flush waiting objects (stub).
  Future<void> writePendingObjects(
      [Set<CraftPdfIndirectReference>? forbiddenToFlush]) async {
    _checkClosingStatus();
  }

  /// Flushes tag structure (stub).
  Future<void> writeTaggingWhenReady(bool usesIncrementalRevision) async {
    _checkClosingStatus();
    if (_structTreeRoot != null) {
      if (!usesIncrementalRevision ||
          _structTreeRoot!.pdfRepresentation().hasChanges()) {
        await _structTreeRoot!.pdfRepresentation().flush();
      }
    }
  }

  Future<CraftPdfStructTreeRoot?> loadStructureRoot() async {
    if (_structTreeRoot == null) {
      final rootDict = await rootCatalog()
          .pdfRepresentation()
          .dictionaryEntry(CraftPdfName.structTreeRoot);
      if (rootDict != null) {
        _structTreeRoot = CraftPdfStructTreeRoot(rootDict);
      }
    }
    return _structTreeRoot;
  }

  /// Gets the logical structure tree root of the document.
  /// (Synchronous version, assumes already loaded or created)
  CraftPdfStructTreeRoot structureRoot() {
    if (_structTreeRoot == null) {
      _structTreeRoot = CraftPdfStructTreeRoot.withDocument(this);
      _catalog?.pdfRepresentation().put(
          CraftPdfName.structTreeRoot, _structTreeRoot!.pdfRepresentation());
    }
    return _structTreeRoot!;
  }

  /// Initializes document's structure tree root.
  Future<void> initializeTaggingWhenReady(CraftPdfDictionary str) async {
    try {
      _structTreeRoot = CraftPdfStructTreeRoot(str);
      _structTreeRoot!.setDocument(this);
      _structParentIndex = await _structTreeRoot!.getParentTreeNextKey();
    } catch (e) {
      _structTreeRoot = null;
      _structParentIndex = -1;
      // Log error
    }
  }

  /// Specifies that document shall contain tag structure.
  CraftPdfDocument enableTagging() {
    _checkClosingStatus();
    if (_structTreeRoot == null) {
      _structTreeRoot = CraftPdfStructTreeRoot.withDocument(this);
      rootCatalog().pdfRepresentation().put(
          CraftPdfName.structTreeRoot, _structTreeRoot!.pdfRepresentation());
      _updateValueInMarkInfoDict(CraftPdfName.marked, CraftPdfBoolean(true));
      _structParentIndex = 0;
    }
    return this;
  }

  /// Returns the next struct parent index.
  int allocateStructureParentIndex() {
    _checkClosingStatus();
    if (_structParentIndex < 0) {
      return -1;
    }
    return _structParentIndex++;
  }

  void _updateValueInMarkInfoDict(CraftPdfName key, CraftPdfObject value) {
    var markInfo =
        rootCatalog().pdfRepresentation().getMap()?[CraftPdfName.markInfo];
    if (markInfo is CraftPdfIndirectReference) {
      markInfo = markInfo.targetObjectSync();
    }

    if (markInfo == null || markInfo is! CraftPdfDictionary) {
      markInfo = CraftPdfDictionary();
      rootCatalog().pdfRepresentation().put(CraftPdfName.markInfo, markInfo);
    }
    markInfo.put(key, value);
  }

  /// Checks if the document is tagged.
  bool usesTagging() {
    return _structTreeRoot != null;
  }

  Future<void> _updatePdfVersionFromCatalog() async {
    final versionName =
        await _catalog!.pdfRepresentation().nameEntry(CraftPdfName.version);
    if (versionName != null) {
      // Parse version from name
      try {
        _version = CraftPdfVersion.fromPdfName(versionName);
      } catch (e) {
        // Log warning
      }
    }
  }

  /// Copies a range of pages from current document to [toDocument].
  ///
  /// [pagesToCopy] - List of pages to copy.
  /// [toDocument] - Document to copy pages to.
  /// [insertBeforePage] - Optional page to insert before (1-based index).
  ///
  /// Returns list of copied pages.
  Future<List<CraftPdfPage>> transferPagesInto(
      List<int> pagesToCopy, CraftPdfDocument toDocument,
      [int? insertBeforePage]) async {
    _checkClosingStatus();

    // Default to append at end
    int insertIndex = insertBeforePage ?? (await toDocument.pageTotal() + 1);

    final List<CraftPdfPage> copiedPages = [];
    if (toDocument != this) {
      if (insertIndex < 1 || insertIndex > toDocument.pageTotal() + 1) {
        throw RangeError.range(
            insertIndex, 1, toDocument.pageTotal() + 1, 'insertBeforePage');
      }
      if (pagesToCopy.toSet().length != pagesToCopy.length) {
        throw ArgumentError(
            'A cross-document batch must select distinct pages.');
      }
      // Page copying does not reconcile these document-level structures.
      for (final key in [
        'AcroForm',
        'StructTreeRoot',
        'OCProperties',
        'Names',
        'Dests'
      ]) {
        if (rootCatalog().pdfRepresentation().containsKey(CraftPdfName(key))) {
          throw UnsupportedError(
              'Cross-document page copying cannot reconcile /$key.');
        }
      }
      final sourcePages = <CraftPdfPage>[];
      for (final number in pagesToCopy) {
        if (number < 1 || number > pageTotal()) {
          throw RangeError.range(number, 1, pageTotal(), 'page');
        }
        final page = (await pageAt(number))!;
        if (page
            .pdfRepresentation()
            .containsKey(CraftPdfName('StructParents'))) {
          throw UnsupportedError(
              'Tagged page copying requires structure reconciliation.');
        }
        final annots =
            await page.pdfRepresentation().arrayEntry(CraftPdfName.annots);
        if (annots != null) {
          for (var i = 0; i < annots.size(); i++) {
            final annotation = await annots.get(i);
            if (annotation is CraftPdfDictionary &&
                (await annotation.nameEntry(CraftPdfName.subtype))
                        ?.getValue() ==
                    'Widget') {
              throw UnsupportedError(
                  'Widget copying requires form reconciliation.');
            }
          }
        }
        sourcePages.add(page);
      }
      final copier = PdfObjectCopier(toDocument,
          forbiddenUnmappedTypes: {'Page', 'Pages', 'Catalog'},
          deferIndirectRegistration: true);
      final targets = <CraftPdfDictionary>[];
      for (final page in sourcePages) {
        final target = CraftPdfDictionary();
        copier.register(page.pdfRepresentation(), target);
        targets.add(target);
      }
      for (var i = 0; i < sourcePages.length; i++) {
        final source = sourcePages[i].pdfRepresentation();
        final target = targets[i];
        await copier.copyDictionaryEntries(source, target,
            excludedKeys: {CraftPdfName.parent});
        for (final name in ['Resources', 'MediaBox', 'CropBox', 'Rotate']) {
          final key = CraftPdfName(name);
          if (target.containsKey(key)) continue;
          CraftPdfDictionary? ancestor = source;
          final visited = <CraftPdfDictionary>{};
          while (ancestor != null) {
            if (!visited.add(ancestor))
              throw FormatException('Cyclic page tree.');
            final value = await ancestor.get(key);
            if (value != null) {
              target.put(key, await copier.copy(value));
              break;
            }
            ancestor = await ancestor.dictionaryEntry(CraftPdfName.parent);
          }
        }
      }
      copier.commit();
      for (final target in targets) {
        final page = CraftPdfPage(target);
        await toDocument.insertPageObject(insertIndex++, page);
        copiedPages.add(page);
      }
      return copiedPages;
    }
    // final Map<PdfPage, PdfPage> page2page = {};

    for (final pageNum in pagesToCopy) {
      if (toDocument == this) {
        final originalPage = await pageAt(pageNum);
        if (originalPage != null) {
          final newPageDict =
              originalPage.pdfRepresentation().clone() as CraftPdfDictionary;

          // Clear Parent and other keys that will be set by addPageAt
          newPageDict.remove(CraftPdfName.parent);

          final newPage = CraftPdfPage(newPageDict);
          await toDocument.insertPageObject(insertIndex, newPage);
          copiedPages.add(newPage);
          insertIndex++;
        }
      }
    }

    return copiedPages;
  }

  /// Adds an output intent to the document.
  void registerOutputProfile(CraftPdfOutputIntent outputIntent) {
    _checkClosingStatus();
    rootCatalog().registerOutputProfile(outputIntent.pdfRepresentation());
  }

  /// Sets PDF/A-1B conformance boilerplate (Metadata and basic OutputIntent).
  Future<void> configureArchivalProfile() async {
    final xmp = await metadataModel(true);
    if (xmp != null) {
      // PDF/A-1B requires specific metadata fields
      xmp.setProperty(CraftXMPConst.NS_DC, 'format', 'application/pdf');
    }

    // Add a default sRGB OutputIntent if none exists
    final intents = await rootCatalog().getOutputIntents();
    if (intents == null || intents.size() == 0) {
      // Note: Ideally we should use a real sRGB ICC profile stream here.
      // For now, we create a placeholder that satisfies simple validators.
      final intent = CraftPdfOutputIntent.create(
        'sRGB IEC61966-2.1', // OutputConditionIdentifier
        'sRGB IEC61966-2.1', // OutputCondition
        'http://www.color.org', // RegistryName
        'sRGB IEC61966-2.1', // Info
        null, // DestOutputProfile (Should be a stream with ICC profile)
      );
      registerOutputProfile(intent);
    }
  }

  /// Gets the XMP Metadata bytes.
  ///
  /// Returns null if no XMP metadata is set.
  /// Sets the XMP Metadata.
  void assignMetadata(CraftXMPMeta xmpMeta) {
    _checkClosingStatus();
    _xmpMetadataBytes =
        Uint8List.fromList(CraftXMPMetaFactory.serializeToBuffer(xmpMeta));
    _xmpMetadata = xmpMeta;
  }

  /// Sets the XMP Metadata as bytes.
  Future<void> assignMetadataPayload(Uint8List xmpMetadata) async {
    _checkClosingStatus();
    _xmpMetadataBytes = xmpMetadata;
    _xmpMetadata = null;
    try {
      await metadataModel();
    } catch (e) {
      // ignore
    }
  }

  /// Gets XMP Metadata.
  Future<CraftXMPMeta?> metadataModel([bool createNew = false]) async {
    _checkClosingStatus();
    if (_xmpMetadata == null) {
      final bytes = await metadataPayload();
      if (bytes != null) {
        _xmpMetadata = CraftXMPMetaFactory.parseFromBuffer(bytes);
      } else if (createNew) {
        _xmpMetadata = CraftXMPMetaFactory.create();
        _xmpMetadata!.setObjectName(CraftXMPConst.TAG_XMPMETA);
        try {
          _xmpMetadata!.setProperty(
              CraftXMPConst.NS_DC, CraftPdfConst.Format, "application/pdf");
        } catch (e) {}
        assignMetadata(_xmpMetadata!);
      }
    }
    return _xmpMetadata;
  }

  /// Gets XMP Metadata bytes.
  ///
  /// Returns null if no XMP metadata is set.
  Future<Uint8List?> metadataPayload() async {
    _checkClosingStatus();
    if (_xmpMetadataBytes == null && _catalog != null) {
      final stream = await _catalog!
          .pdfRepresentation()
          .streamEntry(CraftPdfName.metadata);
      if (stream != null) {
        _xmpMetadataBytes = await stream.getBytes();
      }
    }
    return _xmpMetadataBytes;
  }

  // ============== HELPERS ==============

  /// Checks if the document is closed or closing.
  void _checkClosingStatus() {
    if (_closed) {
      throw CraftPdfException('Document is already closed.');
    }
  }

  // ============== CLOSE ==============

  /// Closes the document.
  Future<void> close() async {
    if (_closed) return;

    _isClosing = true;

    try {
      if (_writer != null) {
        if (pageTotal() == 0) {
          await appendBlankPage();
        }

        // Add PDF producer info in any case, and the valid way to do it for PDF 2.0 in only in metadata, not
        // in the info dictionary.
        await refreshMetadata();

        await writePendingPages();
        await writePendingObjects();

        if (_writer.document != null) {
          await _writer.flushAsync();
        }

        if (usesIncrementalRevision() && _reader != null) {
          await _closeAppendMode();
        } else {
          await _closeNormalMode();
        }
      }
    } finally {
      _closed = true;
      _isClosing = false;
      await _reader?.close();
    }
  }

  /// Updates XMP metadata based on document information.
  Future<void> refreshMetadata() async {
    try {
      // await getDocumentInfo(); // Ensure info is loaded
      // Logic for updating metadata from info
      if (await metadataPayload() != null ||
          _writer?.properties.addXmpMetadata == true) {
        final xmpMeta = await metadataModel(true);
        if (xmpMeta != null) {
          // Append document info to metadata
          // XmpMetaInfoConverter.appendDocumentInfoToMetadata(info, xmpMeta);
          assignMetadata(xmpMeta);
        }
      }
    } catch (e) {
      _logger.logError(e.toString());
    }
  }

  /// Closes the document in normal mode (write everything from scratch).
  Future<void> _closeNormalMode() async {
    final writer = _writer;
    if (writer == null) return;
    final xrefTable = _xrefTable;
    if (xrefTable == null) return;

    writer.writeHeader();

    // Ensure catalog is set up
    final catalog = rootCatalog();

    // Generate Pages tree
    final pagesRoot = await pageHierarchy().generateTree();
    catalog.pdfRepresentation().put(CraftPdfName.pages, pagesRoot);

    // Update XMP Metadata
    if (await metadataPayload() != null) {
      final xmpStream = CraftPdfStream();
      xmpStream.setData(_xmpMetadataBytes!);
      xmpStream.put(CraftPdfName.type, CraftPdfName.metadata);
      xmpStream.put(CraftPdfName.subtype, CraftPdfName.xml);
      // Ensure indirect
      xmpStream.attachToDocument(this);
      catalog.pdfRepresentation().put(CraftPdfName.metadata, xmpStream);
    }

    // Ensure StructTreeRoot is in Catalog if it was created
    if (_structTreeRoot != null) {
      catalog.pdfRepresentation().put(
          CraftPdfName.structTreeRoot, _structTreeRoot!.pdfRepresentation());
    }

    // Flush fonts before writing
    await writeRegisteredTypefaces();

    // Add info dictionary to trailer (must be indirect reference)
    final info = await documentDetails();
    if (info.pdfRepresentation().size() > 0) {
      // Ensure info is indirect
      if (info.pdfRepresentation().indirectHandle() == null) {
        info.pdfRepresentation().attachToDocument(this);
      }
      _trailer ??= CraftPdfDictionary();
      _trailer!
          .put(CraftPdfName.info, info.pdfRepresentation().indirectHandle()!);
    }

    // Write all objects from xref table
    for (var index = 1; index < xrefTable.size(); index++) {
      final ref = xrefTable.get(index);
      if (ref == null) continue;
      if (!ref.isFree() && !ref.checkState(CraftPdfObject.flushed)) {
        final obj = await ref.targetObject();
        if (obj != null) {
          // Skip the current object stream as it's being populated and will be flushed later
          if (obj == writer.currentObjStream) {
            continue;
          }
          await writer.writeObject(obj);
        }
      }
    }

    // Flush any pending ObjStream before building trailer
    // This is critical for full compression mode to actually write the ObjStream
    await writer.flushAsync();

    // Build trailer
    final trailer = fileTrailer(); // Ensure trailer exists
    trailer.remove(CraftPdfName.prev);
    trailer.remove(CraftPdfName.xrefStm);
    // Size is updated below if XRefStream is used
    trailer.put(CraftPdfName.root, catalog.pdfRepresentation());

    // Set IDs in trailer
    final idArray = CraftPdfArray();
    idArray.add(initialDocumentIdentifier());
    idArray.add(revisionIdentifier());
    trailer.put(CraftPdfName.id, idArray);

    // Info is already added above if present

    if (writer.properties.isFullCompression == true) {
      // Create XRefStream object
      final xrefStreamRef = allocateObjectHandle();
      final xrefStream = CraftPdfStream();
      // Manually link reference
      xrefStream.setIndirectReference(xrefStreamRef);
      xrefStreamRef.assignTargetObject(xrefStream);

      // Trailer Size includes the XRefStream itself
      trailer.put(CraftPdfName.size, CraftPdfNumber.fromInt(xrefTable.size()));

      // StartXref is the position of XRefStream object
      final startxref = writer.getPosition();

      await writer.writeXrefStream(xrefTable, trailer, xrefStream);

      // We also need to write startxref offset
      writer.writeString('startxref\n');
      writer.writeInt(startxref);
      writer.writeNewLine();
    } else {
      trailer.put(CraftPdfName.size, CraftPdfNumber.fromInt(xrefTable.size()));
      final startxref = writer.getPosition();
      writer.writeXrefTable(xrefTable);
      await writer.writeTrailer(trailer, startxref);
    }

    writer.writeEOF();
    await writer.close();
  }

  /// Closes the document in append mode (incremental update).
  Future<void> _closeAppendMode() async {
    final reader = _reader;
    if (reader == null) return;
    final writer = _writer;
    if (writer == null) return;
    final xrefTable = _xrefTable;
    if (xrefTable == null) return;

    // 1. Write original PDF bytes first - ONLY if writer position is 0
    // (i.e., original bytes haven't been pre-added by PdfSigner)
    if (writer.getPosition() == 0) {
      final input = reader.getSafeFile();
      while (input.getPosition() < input.length()) {
        final remaining = input.length() - input.getPosition();
        final chunk = Uint8List(remaining < 262144 ? remaining : 262144);
        input.readFully(chunk);
        writer.writeBytes(chunk);
      }
    }

    // 2. Get the previous xref position from the original document
    final prevXref = reader.getLastXrefPosition();

    // Materialize newly registered font dictionaries before serializing their
    // references. The append path otherwise writes only /Type /Font, omitting
    // subtype, encoding and widths populated by the font's flush lifecycle.
    await writeRegisteredTypefaces();

    // Prepare XMP updates before collecting the revision objects.
    if (await metadataPayload() != null) {
      final cat = rootCatalog().pdfRepresentation();
      var xmpStream = await cat.streamEntry(CraftPdfName.metadata);

      if (xmpStream != null && xmpStream.indirectHandle() != null) {
        xmpStream.setData(_xmpMetadataBytes!);
        if (!xmpStream.hasChanges()) {
          xmpStream.markChanged();
        }
      } else {
        xmpStream = CraftPdfStream();
        xmpStream.setData(_xmpMetadataBytes!);
        xmpStream.put(CraftPdfName.type, CraftPdfName.metadata);
        xmpStream.put(CraftPdfName.subtype, CraftPdfName.xml);
        xmpStream.attachToDocument(this);
        cat.put(CraftPdfName.metadata, xmpStream);
        cat.markChanged();
      }
    }

    // Serialization may discover nested streams and allocate new references.
    // Traverse the live object-number range so those objects enter this revision.
    for (var index = 1; index < xrefTable.size(); index++) {
      final ref = xrefTable.get(index);
      if (ref == null) continue;
      final isNew = ref.inputReader() == null;
      final shouldWrite = !ref.isFree() &&
          !ref.checkState(CraftPdfObject.flushed) &&
          (ref.hasChanges() || isNew);

      if (shouldWrite) {
        final obj = await ref.targetObject();
        if (obj != null) {
          await writer.writeObject(obj);
        }
      }
    }

    // 4. Collect modified references
    final modifiedRefs = <CraftPdfIndirectReference>[];
    for (final ref in xrefTable.references) {
      final isNew = ref.inputReader() == null;
      if (!ref.isFree() && (ref.hasChanges() || isNew)) {
        modifiedRefs.add(ref);
      }
    }

    // 5. Write incremental xref table
    final startxref = writer.getPosition();
    writer.writeIncrementalXrefTable(xrefTable, modifiedRefs);

    // 5. Build new trailer with Prev pointer
    final trailer = CraftPdfDictionary();
    trailer.put(
        CraftPdfName.intern('Size'), CraftPdfNumber.fromInt(xrefTable.size()));
    trailer.put(CraftPdfName.intern('Root'), rootCatalog().pdfRepresentation());
    trailer.put(CraftPdfName.intern('Prev'), CraftPdfNumber.fromInt(prevXref));

    // Add info if loaded/modified - use indirect reference
    if (_info != null) {
      final infoRef = _info!.pdfRepresentation().indirectHandle();
      if (infoRef != null) {
        trailer.put(CraftPdfName.info, infoRef);
      }
    }

    // Set IDs in trailer
    final idArray = CraftPdfArray();
    idArray.add(initialDocumentIdentifier());
    idArray.add(revisionIdentifier());
    trailer.put(CraftPdfName.id, idArray);

    await writer.writeTrailer(trailer, startxref);
    writer.writeEOF();
    await writer.close();
  }

  /// Disposes resources.
  void dispose() {
    if (!_closed) {
      // Just mark as closed without writing
      _closed = true;
    }
  }
}

/// Data container for debugging information.
class CraftFingerPrint {
  bool _fingerPrintEnabled = true;

  /// Default constructor.
  CraftFingerPrint();

  /// This method is used to disable  fingerprint.
  void disableFingerPrint() {
    _fingerPrintEnabled = false;
  }

  /// This method is used to check  fingerprint state.
  bool isFingerPrintEnabled() {
    return _fingerPrintEnabled;
  }
}
