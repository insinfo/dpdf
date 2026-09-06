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
import 'pdf_page.dart';
import 'pdf_pages_tree.dart';
import 'pdf_reader.dart';
import 'pdf_writer.dart';
import 'pdf_xref_table.dart';
import 'pdf_version.dart';
import 'pdf_output_intent.dart';
import 'package:dpdf/src/commons/_log_manager.dart';
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

/// Main entry point to work with PDF document.
///
/// This is a port of 's PdfDocument class from C# to Dart.
class PdfDocument {
  /// PDF names to remove from original trailer (used in append mode)
  // ignore: unused_field
  static final List<PdfName> _pdfNamesToRemoveFromOriginalTrailer = [
    PdfName.encrypt,
    PdfName.size,
    PdfName.prev,
    PdfName.root,
    PdfName.info,
    PdfName.id,
  ];

  /// List of loaded fonts to prevent duplication and enable flushing.
  final Map<PdfIndirectReference, PdfFont> _documentFonts = {};

  /// List of indirect objects used in the document.
  PdfXrefTable? _xrefTable;

  /// PdfWriter associated with the document.
  static final _logger = LogManager.getLoggerByName('PdfDocument');
  final PdfWriter? _writer;

  /// PdfReader associated with the document.
  PdfReader? _reader;

  /// Document catalog.
  PdfCatalog? _catalog;

  /// Document trailer.
  PdfDictionary? _trailer;

  /// Document version.
  PdfVersion? _version;

  /// Encryption handler.
  PdfEncryption? _encryption;


  /// Whether the document is closed.
  bool _closed = false;

  /// Whether the closing process has started.
  bool _isClosing = false;

  /// Default page size.
  PageSize _defaultPageSize = PageSize.defaultSize;

  /// Default font - lazy initialized.
  PdfFont? _defaultFont;

  /// Stamping properties.
  final StampingProperties? _properties;

  /// Original document ID.
  PdfString? _originalDocumentId;

  /// Modified document ID.
  PdfString? _modifiedDocumentId;

  /// Document info - lazy initialized.
  PdfDocumentInfo? _info;

  /// XMP Metadata bytes for the document.
  Uint8List? _xmpMetadataBytes;

  /// XMP Metadata which is used to prevent bytes deserialization for a few times on the same bytes.
  XMPMeta? _xmpMetadata;

  // Event handlers map
  final Map<String, List<IEventHandler>> _handlers = {};

  /// Document fingerprints.
  // ignore: unused_field
  FingerPrint? _fingerPrint;

  /// Tag structure context.
  TagStructureContext? _tagStructureContext;

  /// Root of the structure tree.
  PdfStructTreeRoot? _structTreeRoot;

  /// Index for next struct parent.
  int _structParentIndex = 0;

  /// Opens PDF document in reading mode.

  /// Opens PDF document in reading mode.
  ///
  /// [reader] - PDF reader.
  PdfDocument.fromReader(PdfReader reader)
      : _reader = reader,
        _writer = null,
        _properties = null {
    _open(null);
  }

  /// Opens PDF document in writing mode.
  /// Document has no pages when initialized.
  ///
  /// [writer] - PDF writer.
  PdfDocument.fromWriter(PdfWriter writer)
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
  PdfDocument({
    PdfReader? reader,
    PdfWriter? writer,
    StampingProperties? properties,
  })  : _reader = reader,
        _writer = writer,
        _properties = properties {
    _open(null);
  }

  /// Initializes document.
  void _open(PdfVersion? newPdfVersion) {
    _fingerPrint = FingerPrint();
    // Initialize xref table
    if (_reader != null) {
      _xrefTable = _reader!.xref;
      _version = _reader!.getPdfVersion();
      _reader!.setDocument(this);
    } else {
      _xrefTable = PdfXrefTable();
      _version = PdfVersion.PDF_1_7;
    }

    // Set document reference in writer
    if (_writer != null) {
      _writer.document = this;

      if (_reader == null) {
        // New document - create catalog and add creation date
        _catalog = PdfCatalog(PdfDictionary());
        _catalog!.getPdfObject().makeIndirect(this);
        getDocumentInfoSync().addCreationDate();
      }
      getDocumentInfoSync().addModDate();

      // Initialize trailer
      if (_trailer == null) {
        _trailer = PdfDictionary();
      }

      // We keep the original trailer of the document to preserve the original document keys,
      // but we have to remove all standard keys that can occur in the trailer to avoid invalid pdfs
      if (_trailer!.size() > 0 &&
          _reader != null &&
          !isAppendMode()) {
        final keysToRemove = [
          PdfName.root,
          PdfName.info,
          PdfName.id,
          PdfName.prev,
          PdfName.size,
          PdfName.xrefStm,
          PdfName.encrypt,
          PdfName.index,
          PdfName.w
        ];
        for (final key in keysToRemove) {
          _trailer!.remove(key);
        }
      }

      // Ensure modified ID is updated or preserved
      if (_trailer!.containsKey(PdfName.id)) {
        // In append mode, usually we preserve unless we specifically want to update.
      } else {
        // Create IDs if missing
        final idArray = PdfArray();
        idArray.add(getOriginalDocumentId());
        idArray.add(getModifiedDocumentId());
        _trailer!.put(PdfName.id, idArray);
      }

      // Set root reference in trailer
      if (_catalog != null) {
        _trailer!.put(PdfName.root, _catalog!.getPdfObject());
      }
    }

    _xrefTable?.initFreeReferencesList(this);
  }

  /// Loads document from reader. Must be called after constructor for reading mode.
  Future<void> load() async {
    if (_reader == null) return;

    await _reader!.read();

    // Get catalog from reader's trailer
    final catalogDict = await _reader!.getCatalog();
    if (catalogDict == null) {
      throw PdfException('Corrupted root entry in trailer');
    }

    // Create catalog wrapper
    _catalog = PdfCatalog(catalogDict);
    
    // Ensure catalog's indirect reference has this document set
    final catRef = catalogDict.getIndirectReference();
    if (catRef != null) {
      catRef.setDocument(this);
    }

    // Get trailer from reader
    _trailer = _reader!.trailer;

    // Load Document IDs
    final idArray = await _trailer?.getAsArray(PdfName.id);
    if (idArray != null) {
      if (idArray.size() > 0) {
        _originalDocumentId = await idArray.getAsString(0);
      }
      if (idArray.size() > 1) {
        _modifiedDocumentId = await idArray.getAsString(1);
      }
    }

    // Initialize version from reader
    _version = _reader!.getPdfVersion();

    // Initialize Pages Tree from saved catalog
    final tree = getPagesTree();
    await tree.init();

    // Initialize Tag Structure if present
    final str = await _catalog!.getPdfObject().getAsDictionary(PdfName.structTreeRoot);
    if (str != null) {
      await tryInitTagStructure(str);
    }

    // Update version from catalog
    await _updatePdfVersionFromCatalog();
  }

  /// Factory method to open document for reading.
  static Future<PdfDocument> open(PdfReader reader) async {
    final doc = PdfDocument.fromReader(reader);
    await doc.load();
    return doc;
  }

  /// Factory method to create new document.
  static PdfDocument create(PdfWriter writer) {
    return PdfDocument.fromWriter(writer);
  }

  // ============== GETTERS ==============

  /// Gets PdfReader associated with the document.
  PdfReader? getReader() => _reader;

  /// Gets PdfWriter associated with the document.
  PdfWriter? getWriter() => _writer;

  /// Gets document catalog.
  PdfCatalog getCatalog() {
    if (_catalog == null) {
      _catalog = PdfCatalog(PdfDictionary());
      _catalog!.getPdfObject().makeIndirect(this);
      if (_trailer != null) {
        _trailer!.put(PdfName.root, _catalog!.getPdfObject());
      }
    }
    return _catalog!;
  }

  /// Gets document trailer.
  PdfDictionary getTrailer() {
    _trailer ??= PdfDictionary();
    return _trailer!;
  }

  /// Gets xref table.
  PdfXrefTable? getXrefTable() => _xrefTable;

  /// Alias for getXrefTable for compatibility.
  PdfXrefTable getXref() => _xrefTable ?? PdfXrefTable();

  /// Gets encryption handler.
  PdfEncryption? getEncryption() => _encryption;

  /// Gets document version.
  PdfVersion? getVersion() => _version;

  /// Returns true if document is closed.
  bool isClosed() => _closed;

  /// Returns true if closing process has started.
  bool isClosing() => _isClosing;

  /// Gets default page size.
  PageSize getDefaultPageSize() => _defaultPageSize;

  /// Sets default page size.
  void setDefaultPageSize(PageSize pageSize) {
    _defaultPageSize = pageSize;
  }

  /// Gets the default font for the document.
  ///
  /// The default font is lazily initialized using Helvetica.
  /// Returns the default font, or null if creation fails.
  PdfFont? getDefaultFont() {
    if (_defaultFont == null) {
      try {
        // Use Helvetica as the default font
        _defaultFont = PdfFontFactory.createFont('Helvetica');
        if (_writer != null && _defaultFont != null) {
          _defaultFont!.makeIndirect(this);
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
  Future<PdfFont?> getFont(PdfDictionary fontDictionary) async {
    final ref = fontDictionary.getIndirectReference();
    if (ref != null && _documentFonts.containsKey(ref)) {
      return _documentFonts[ref];
    }
    try {
      final font =
          await PdfFontFactory.createFontFromDictionary(fontDictionary);
      if (font != null) {
        // If we created a font, we should add it to our tracking map
        // but only if it has an indirect reference (which it usually does or will)
        return addFont(font);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Adds a [PdfFont] instance to this document so that this font is flushed automatically
  /// on document close.
  PdfFont addFont(PdfFont font) {
    font.makeIndirect(this);
    // font.setForbidRelease(); // Not implemented yet
    final ref = font.getPdfObject().getIndirectReference();
    if (ref != null) {
      _documentFonts[ref] = font;
    }
    return font;
  }

  /// List all newly added or loaded fonts.
  List<PdfFont> getDocumentFonts() {
    return _documentFonts.values.toList();
  }

  /// Adds event handler.
  void addEventHandler(String type, IEventHandler handler) {
    _handlers.putIfAbsent(type, () => []).add(handler);
  }

  /// Removes event handler.
  void removeEventHandler(String type, IEventHandler handler) {
    _handlers[type]?.remove(handler);
  }

  /// Dispatches event.
  void dispatchEvent(IEvent event) {
    final list = _handlers[event.eventType];
    if (list != null) {
      for (final handler in list) {
        handler.onEvent(event);
      }
    }
  }

  // ============== PAGES ==============

  /// Gets pages tree.
  PdfPagesTree getPagesTree() {
    final tree = getCatalog().getPageTree();
    tree.setDocument(this);
    return tree;
  }

  /// Creates and adds new page to the end of document.
  Future<PdfPage> addNewPage([PageSize? pageSize]) async {
    _checkClosingStatus();
    final page = PdfPage(PdfDictionary());
    page.setMediaBox(pageSize ?? _defaultPageSize);
    await getPagesTree().addPage(page, this);

    dispatchEvent(
        PdfDocumentEvent(PdfDocumentEvent.startPage, page.getPdfObject()));
    dispatchEvent(
        PdfDocumentEvent(PdfDocumentEvent.insertPage, page.getPdfObject()));

    return page;
  }

  /// Creates and inserts new page at the specified position (1-based index).
  ///
  /// [index] - Position to insert page to (1-based)
  /// [pageSize] - Optional size of the new page
  Future<PdfPage> addNewPageAt(int index, [PageSize? pageSize]) async {
    _checkClosingStatus();
    final page = PdfPage(PdfDictionary());
    page.setMediaBox(pageSize ?? _defaultPageSize);
    await getPagesTree().addPageAt(index, page, this);

    dispatchEvent(
        PdfDocumentEvent(PdfDocumentEvent.startPage, page.getPdfObject()));
    dispatchEvent(
        PdfDocumentEvent(PdfDocumentEvent.insertPage, page.getPdfObject()));

    return page;
  }

  /// Adds existing page to the end of document.
  Future<PdfPage> addPage(PdfPage page) async {
    _checkClosingStatus();
    await getPagesTree().addPage(page, this);
    dispatchEvent(
        PdfDocumentEvent(PdfDocumentEvent.insertPage, page.getPdfObject()));
    return page;
  }

  /// Inserts existing page at the specified position (1-based index).
  ///
  /// [index] - Position to insert page to (1-based)
  /// [page] - The page to insert
  Future<PdfPage> addPageAt(int index, PdfPage page) async {
    _checkClosingStatus();
    await getPagesTree().addPageAt(index, page, this);
    dispatchEvent(
        PdfDocumentEvent(PdfDocumentEvent.insertPage, page.getPdfObject()));
    return page;
  }

  /// Gets the page by page number (1-based).
  Future<PdfPage?> getPage(int pageNumber) async {
    return await getPagesTree().getPage(pageNumber);
  }

  /// Gets the first page of the document.
  Future<PdfPage?> getFirstPage() async {
    if (getNumberOfPages() > 0) {
      return await getPage(1);
    }
    return null;
  }

  /// Gets the last page of the document.
  Future<PdfPage?> getLastPage() async {
    final numPages = getNumberOfPages();
    if (numPages > 0) {
      return await getPage(numPages);
    }
    return null;
  }

  /// Gets number of pages in the document.
  int getNumberOfPages() {
    return getPagesTree().getNumberOfPages();
  }

  /// Gets the page by its PdfDictionary.
  ///
  /// Returns null if the page is not found.
  Future<PdfPage?> getPageByDictionary(PdfDictionary pageDictionary) async {
    return await getPagesTree().getPageByDictionary(pageDictionary);
  }

  /// Gets page number by page.
  int getPageNumber(PdfPage page) {
    return getPagesTree().getPageNumber(page);
  }

  /// Removes the page at the specified position (1-based index).
  ///
  /// [pageNum] - the one-based index of the PdfPage to be removed.
  Future<void> removePageAt(int pageNum) async {
    _checkClosingStatus();
    final removedPage = await getPage(pageNum);
    if (removedPage != null) {
      // Remove outlines
      await getCatalog().removeOutlines(removedPage);

      // Remove unused widgets
      _removeUnusedWidgetsFromFields(removedPage);

      // Remove tags
      if (isTagged()) {
        getTagStructureContext()?.removePageTags(removedPage);
      }

      // Remove parent reference from page dictionary
      removedPage.getPdfObject().remove(PdfName.parent);
      // Mark the indirect reference as free
      final ref = removedPage.getPdfObject().getIndirectReference();
      if (ref != null) {
        ref.setState(PdfObject.free);
      }
      dispatchEvent(PdfDocumentEvent(
          PdfDocumentEvent.removePage, removedPage.getPdfObject()));
    }
    await getPagesTree().removePage(pageNum);
  }

  /// Removes all widgets associated with a given page from AcroForm structure.
  void _removeUnusedWidgetsFromFields(PdfPage page) {
    if (page.isFlushed()) {
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
  Future<void> addFileAttachment(String key, PdfFileSpec fs) async {
    _checkClosingStatus();
    await getCatalog().addNameToNameTree(
        PdfString(key), fs.getPdfObject(), PdfName.embeddedFiles);
  }

  /// Adds file associated with PDF document as a whole.
  Future<void> addAssociatedFile(String description, PdfFileSpec fs) async {
    final fsDict = fs.getPdfObject();
    if (!fsDict.containsKey(PdfName.afRelationship)) {
      // Log error or throw
    }
    PdfArray? afArray =
        await getCatalog().getPdfObject().getAsArray(PdfName.af);
    if (afArray == null) {
      afArray = PdfArray();
      afArray.makeIndirect(this);
      getCatalog().put(PdfName.af, afArray);
    }
    afArray.add(fs.getPdfObject());
    await addFileAttachment(description, fs);
  }

  /// Adds a named destination.
  Future<void> addNamedDestination(String key, PdfObject value) async {
    await getCatalog().addNamedDestination(PdfString(key), value);
  }

  /// Gets the outlines of the document.
  Future<PdfOutline?> getOutlines(bool updateOutlines) async {
    _checkClosingStatus();
    return await getCatalog().getOutlines(updateOutlines);
  }

  /// Initializes an outline tree of the document.
  void initializeOutlines() {
    _checkClosingStatus();
    if (!hasOutlines()) {
      PdfOutline.createRoot(this);
    }
  }

  /// Indicates if the document has any outlines.
  bool hasOutlines() {
    return getCatalog().hasOutlines();
  }

  /// Gets page labels.
  Future<List<String>?> getPageLabels() async {
    // Stub
    return null;
  }

  /// Checks ISO conformance.
  void checkIsoConformance(dynamic validationContext) {
    // Stub
  }

  /// Removes the specified page from this document.
  ///
  /// Returns true if this document contained the specified page.
  Future<bool> removePage(PdfPage page) async {
    _checkClosingStatus();
    final pageNum = getPageNumber(page);
    if (pageNum >= 1) {
      await removePageAt(pageNum);
      return true;
    }
    return false;
  }

  /// Moves page to new place in same document with all it tag structure.
  ///
  /// [page] - page to be moved in document if present
  /// [insertBefore] - indicates before which page new one will be inserted to (1-based)
  Future<bool> movePage(PdfPage page, int insertBefore) async {
    _checkClosingStatus();
    final pageNum = getPageNumber(page);
    if (pageNum > 0) {
      await movePageAt(pageNum, insertBefore);
      return true;
    }
    return false;
  }

  /// Moves page to new place in same document with all it tag structure.
  ///
  /// [pageNumber] - number of Page that will be moved (1-based)
  /// [insertBefore] - indicates before which page new one will be inserted to (1-based)
  Future<void> movePageAt(int pageNumber, int insertBefore) async {
    _checkClosingStatus();
    if (insertBefore < 1 || insertBefore > getNumberOfPages() + 1) {
      throw RangeError('Requested page number $insertBefore is out of bounds.');
    }

    // TODO: Tagged PDF support (GetStructTreeRoot)
    // For now we assume no StructTreeRoot updates needed or handled separately.

    // Detach from parent and remove from tree.
    // We use getPagesTree().removePage() directly to avoid 'freeing' the object,
    // which happens in PdfDocument.removePageAt().
    final removedPage = await getPagesTree().removePage(pageNumber);
    if (removedPage == null) {
      // Page not found or error
      return;
    }

    if (insertBefore > pageNumber) {
      insertBefore--;
    }

    // Re-attach page at new location
    await getPagesTree().addPageAt(insertBefore, removedPage, this);
  }

  // ============== OBJECTS ==============

  /// Gets number of indirect objects in the document.
  int getNumberOfPdfObjects() {
    return _xrefTable?.size() ?? 0;
  }

  /// Creates next indirect reference.
  PdfIndirectReference createNextIndirectReference() {
    final objNr = _xrefTable!.size();
    return _xrefTable!.add(PdfIndirectReference(objNr, 0)..setDocument(this))!;
  }

  /// Reads object by indirect reference.
  Future<PdfObject?> readObject(PdfIndirectReference reference) async {
    if (reference.getDocument() != this) {
      throw ArgumentError("Indirect reference does not belong to document");
    }
    if (reference.isFree()) return null;
    if (_reader != null) {
      return await _reader!.readObject(reference.getObjNumber());
    }
    return null;
  }

  /// Gets PdfObject by object number.
  ///
  /// Returns [PdfObject] or null if object not found.
  Future<PdfObject?> getPdfObject(int objNum) async {
    _checkClosingStatus();
    final reference = _xrefTable?.get(objNum);
    if (reference == null) {
      return null;
    }
    return await reference.getRefersTo();
  }

  // ============== APPEND MODE ==============

  /// Returns true if the document is opened in append mode.
  bool isAppendMode() => _properties?.isAppendMode() ?? false;

  /// Gets the stamping properties for this document.
  StampingProperties? getStampingProperties() => _properties;

  // ============== ENCRYPTION ==============

  /// Returns true if the document is encrypted.
  bool isEncrypted() => _encryption != null;

  /// Sets the encryption for the document.
  void setEncryption(PdfEncryption? encryption) {
    _encryption = encryption;
  }

  /// Gets original document id.
  PdfString getOriginalDocumentId() {
    return _originalDocumentId ??=
        PdfString.fromBytes(PdfEncryption.generateNewDocumentId(), true);
  }

  /// Gets modified document id.
  PdfString getModifiedDocumentId() {
    return _modifiedDocumentId ??=
        PdfString.fromBytes(PdfEncryption.generateNewDocumentId(), true);
  }

  // ============== INFO ==============

  /// Gets document information dictionary.
  Future<PdfDocumentInfo> getDocumentInfo() async {
    _checkClosingStatus();
    if (_info == null) {
      final infoDict = _trailer != null ? await _trailer!.getAsDictionary(PdfName.info) : null;
      _info = PdfDocumentInfo(infoDict ?? PdfDictionary());
    }
    return _info!;
  }

  /// Gets the document information synchronously.
  /// If info is not loaded, it creates a new one.
  PdfDocumentInfo getDocumentInfoSync() {
    _checkClosingStatus();
    if (_info == null) {
      PdfDictionary? infoDict;
      if (_trailer != null) {
        var infoObj = _trailer!.getMap()?[PdfName.info];
        if (infoObj is PdfIndirectReference) {
          infoObj = infoObj.getRefersToSync();
        }
        if (infoObj is PdfDictionary) {
          infoDict = infoObj;
        }
      }
      _info = PdfDocumentInfo(infoDict ?? PdfDictionary());
    }
    return _info!;
  }

  // ============== FLUSH ==============

  /// Gets the tag structure context.
  TagStructureContext? getTagStructureContext() {
    if (_tagStructureContext == null) {
      _tagStructureContext = TagStructureContext(this);
    }
    return _tagStructureContext;
  }

  /// Flushes all fonts.
  Future<void> flushFonts() async {
    for (final font in _documentFonts.values) {
      await font.flush();
    }
  }

  /// Flushes pages to free memory (stub).
  Future<void> flushPages() async {
    _checkClosingStatus();
  }

  /// Flush waiting objects (stub).
  Future<void> flushWaitingObjects([Set<PdfIndirectReference>? forbiddenToFlush]) async {
    _checkClosingStatus();
  }

  /// Flushes tag structure (stub).
  Future<void> tryFlushTagStructure(bool isAppendMode) async {
    _checkClosingStatus();
    if (_structTreeRoot != null) {
      if (!isAppendMode || _structTreeRoot!.getPdfObject().isModified()) {
        await _structTreeRoot!.getPdfObject().flush();
      }
    }
  }

  Future<PdfStructTreeRoot?> getStructTreeRootAsync() async {
    if (_structTreeRoot == null) {
      final rootDict = await getCatalog()
          .getPdfObject()
          .getAsDictionary(PdfName.structTreeRoot);
      if (rootDict != null) {
        _structTreeRoot = PdfStructTreeRoot(rootDict);
      }
    }
    return _structTreeRoot;
  }

  /// Gets the logical structure tree root of the document.
  /// (Synchronous version, assumes already loaded or created)
  PdfStructTreeRoot getStructTreeRoot() {
      if (_structTreeRoot == null) {
        _structTreeRoot = PdfStructTreeRoot.withDocument(this);
        _catalog?.getPdfObject().put(PdfName.structTreeRoot, _structTreeRoot!.getPdfObject());
      }
      return _structTreeRoot!;
  }

  /// Initializes document's structure tree root.
  Future<void> tryInitTagStructure(PdfDictionary str) async {
    try {
      _structTreeRoot = PdfStructTreeRoot(str);
      _structTreeRoot!.setDocument(this);
      _structParentIndex = await _structTreeRoot!.getParentTreeNextKey();
    } catch (e) {
      _structTreeRoot = null;
      _structParentIndex = -1;
      // Log error
    }
  }

  /// Specifies that document shall contain tag structure.
  PdfDocument setTagged() {
    _checkClosingStatus();
    if (_structTreeRoot == null) {
      _structTreeRoot = PdfStructTreeRoot.withDocument(this);
      getCatalog().getPdfObject().put(PdfName.structTreeRoot, _structTreeRoot!.getPdfObject());
      _updateValueInMarkInfoDict(PdfName.marked, PdfBoolean(true));
      _structParentIndex = 0;
    }
    return this;
  }

  /// Returns the next struct parent index.
  int getNextStructParentIndex() {
    _checkClosingStatus();
    if (_structParentIndex < 0) {
      return -1;
    }
    return _structParentIndex++;
  }

  void _updateValueInMarkInfoDict(PdfName key, PdfObject value) {
    var markInfo = getCatalog().getPdfObject().getMap()?[PdfName.markInfo];
    if (markInfo is PdfIndirectReference) {
      markInfo = markInfo.getRefersToSync();
    }
    
    if (markInfo == null || markInfo is! PdfDictionary) {
      markInfo = PdfDictionary();
      getCatalog().getPdfObject().put(PdfName.markInfo, markInfo);
    }
    markInfo.put(key, value);
  }

  /// Checks if the document is tagged.
  bool isTagged() {
    return _structTreeRoot != null;
  }

  Future<void> _updatePdfVersionFromCatalog() async {
    final versionName = await _catalog!.getPdfObject().getAsName(PdfName.version);
    if (versionName != null) {
      // Parse version from name
      try {
        _version = PdfVersion.fromPdfName(versionName);
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
  Future<List<PdfPage>> copyPagesTo(
      List<int> pagesToCopy, PdfDocument toDocument,
      [int? insertBeforePage]) async {
    _checkClosingStatus();

    // Default to append at end
    int insertIndex =
        insertBeforePage ?? (await toDocument.getNumberOfPages() + 1);

    final List<PdfPage> copiedPages = [];
    // final Map<PdfPage, PdfPage> page2page = {};

    for (final pageNum in pagesToCopy) {
      if (toDocument == this) {
        final originalPage = await getPage(pageNum);
        if (originalPage != null) {
          final newPageDict = originalPage.getPdfObject().clone() as PdfDictionary;
          
          // Clear Parent and other keys that will be set by addPageAt
          newPageDict.remove(PdfName.parent);
          
          final newPage = PdfPage(newPageDict);
          await toDocument.addPageAt(insertIndex, newPage);
          copiedPages.add(newPage);
          insertIndex++;
        }
      } else {
        // Cross-document copying is a complex task requiring full resource mapping (PdfCopier logic).
        // For now, we only support same-document duplication.
        throw UnimplementedError('Cross-document page copying is not yet implemented.');
      }
    }

    return copiedPages;
  }

  /// Adds an output intent to the document.
  void addOutputIntent(PdfOutputIntent outputIntent) {
    _checkClosingStatus();
    getCatalog().addOutputIntent(outputIntent.getPdfObject());
  }

  /// Sets PDF/A-1B conformance boilerplate (Metadata and basic OutputIntent).
  Future<void> setPdfAConformance() async {
    final xmp = await getXmpMetadata(true);
    if (xmp != null) {
      // PDF/A-1B requires specific metadata fields
      xmp.setProperty(XMPConst.NS_DC, 'format', 'application/pdf');
    }

    // Add a default sRGB OutputIntent if none exists
    final intents = await getCatalog().getOutputIntents();
    if (intents == null || intents.size() == 0) {
      // Note: Ideally we should use a real sRGB ICC profile stream here.
      // For now, we create a placeholder that satisfies simple validators.
      final intent = PdfOutputIntent.create(
        'sRGB IEC61966-2.1', // OutputConditionIdentifier
        'sRGB IEC61966-2.1', // OutputCondition
        'http://www.color.org', // RegistryName
        'sRGB IEC61966-2.1', // Info
        null, // DestOutputProfile (Should be a stream with ICC profile)
      );
      addOutputIntent(intent);
    }
  }

  /// Gets the XMP Metadata bytes.
  ///
  /// Returns null if no XMP metadata is set.
  /// Sets the XMP Metadata.
  void setXmpMetadata(XMPMeta xmpMeta) {
    _checkClosingStatus();
    _xmpMetadataBytes =
        Uint8List.fromList(XMPMetaFactory.serializeToBuffer(xmpMeta));
    _xmpMetadata = xmpMeta;
  }

  /// Sets the XMP Metadata as bytes.
  Future<void> setXmpMetadataBytes(Uint8List xmpMetadata) async {
    _checkClosingStatus();
    _xmpMetadataBytes = xmpMetadata;
    _xmpMetadata = null;
    try {
      await getXmpMetadata();
    } catch (e) {
      // ignore
    }
  }

  /// Gets XMP Metadata.
  Future<XMPMeta?> getXmpMetadata([bool createNew = false]) async {
    _checkClosingStatus();
    if (_xmpMetadata == null) {
      final bytes = await getXmpMetadataBytes();
      if (bytes != null) {
        _xmpMetadata = XMPMetaFactory.parseFromBuffer(bytes);
      } else if (createNew) {
        _xmpMetadata = XMPMetaFactory.create();
        _xmpMetadata!.setObjectName(XMPConst.TAG_XMPMETA);
        try {
          _xmpMetadata!
              .setProperty(XMPConst.NS_DC, PdfConst.Format, "application/pdf");
        } catch (e) {}
        setXmpMetadata(_xmpMetadata!);
      }
    }
    return _xmpMetadata;
  }

  /// Gets XMP Metadata bytes.
  ///
  /// Returns null if no XMP metadata is set.
  Future<Uint8List?> getXmpMetadataBytes() async {
    _checkClosingStatus();
    if (_xmpMetadataBytes == null && _catalog != null) {
      final stream =
          await _catalog!.getPdfObject().getAsStream(PdfName.metadata);
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
      throw PdfException('Document is already closed.');
    }
  }

  // ============== CLOSE ==============

  /// Closes the document.
  Future<void> close() async {
    if (_closed) return;

    _isClosing = true;

    try {
      if (_writer != null) {
        if (getNumberOfPages() == 0) {
          await addNewPage();
        }

        // Add PDF producer info in any case, and the valid way to do it for PDF 2.0 in only in metadata, not
        // in the info dictionary.
        await updateXmpMetadata();

        await flushPages();
        await flushWaitingObjects();

        if (_writer.document != null) {
           await _writer.flushAsync();
        }

        if (isAppendMode() && _reader != null) {
          await _closeAppendMode();
        } else {
          await _closeNormalMode();
        }
      }
    } finally {
      _closed = true;
      _isClosing = false;
    }
  }

  /// Updates XMP metadata based on document information.
  Future<void> updateXmpMetadata() async {
    try {
      // await getDocumentInfo(); // Ensure info is loaded
      // Logic for updating metadata from info
      if (await getXmpMetadataBytes() != null || _writer?.properties.addXmpMetadata == true) {
         final xmpMeta = await getXmpMetadata(true);
         if (xmpMeta != null) {
           // Append document info to metadata
           // XmpMetaInfoConverter.appendDocumentInfoToMetadata(info, xmpMeta);
           setXmpMetadata(xmpMeta);
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
    final catalog = getCatalog();

    // Generate Pages tree
    final pagesRoot = await getPagesTree().generateTree();
    catalog.getPdfObject().put(PdfName.pages, pagesRoot);

    // Update XMP Metadata
    if (await getXmpMetadataBytes() != null) {
      final xmpStream = PdfStream();
      xmpStream.setData(_xmpMetadataBytes!);
      xmpStream.put(PdfName.type, PdfName.metadata);
      xmpStream.put(PdfName.subtype, PdfName.xml);
      // Ensure indirect
      xmpStream.makeIndirect(this);
      catalog.getPdfObject().put(PdfName.metadata, xmpStream);
    }

    // Ensure StructTreeRoot is in Catalog if it was created
    if (_structTreeRoot != null) {
        catalog.getPdfObject().put(PdfName.structTreeRoot, _structTreeRoot!.getPdfObject());
    }

    // Flush fonts before writing
    await flushFonts();

    // Add info dictionary to trailer (must be indirect reference)
    final info = await getDocumentInfo();
    if (info.getPdfObject().size() > 0) {
      // Ensure info is indirect
      if (info.getPdfObject().getIndirectReference() == null) {
        info.getPdfObject().makeIndirect(this);
      }
      _trailer ??= PdfDictionary();
      _trailer!.put(PdfName.info, info.getPdfObject().getIndirectReference()!);
    }

    // Write all objects from xref table
    for (final ref in xrefTable.references) {
      if (!ref.isFree() && !ref.checkState(PdfObject.flushed)) {
        final obj = await ref.getRefersTo();
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
    final trailer = getTrailer(); // Ensure trailer exists
    // Size is updated below if XRefStream is used
    trailer.put(PdfName.root, catalog.getPdfObject());

    // Set IDs in trailer
    final idArray = PdfArray();
    idArray.add(getOriginalDocumentId());
    idArray.add(getModifiedDocumentId());
    trailer.put(PdfName.id, idArray);

    // Info is already added above if present

    if (writer.properties.isFullCompression == true) {
       // Create XRefStream object
       final xrefStreamRef = createNextIndirectReference();
       final xrefStream = PdfStream();
       // Manually link reference
       xrefStream.setIndirectReference(xrefStreamRef);
       xrefStreamRef.setRefersTo(xrefStream);
       
       // Trailer Size includes the XRefStream itself
       trailer.put(PdfName.size, PdfNumber.fromInt(xrefTable.size()));
       
       // StartXref is the position of XRefStream object
       final startxref = writer.getPosition();
       
       await writer.writeXrefStream(xrefTable, trailer, xrefStream);
        
       // We also need to write startxref offset
       writer.writeString('startxref\n');
       writer.writeInt(startxref);
       writer.writeNewLine();
    } else {
       trailer.put(PdfName.size, PdfNumber.fromInt(xrefTable.size()));
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
    final originalBytes = reader.getOriginalBytes();
    if (originalBytes != null && writer.getPosition() == 0) {
      writer.writeBytes(originalBytes);
    }

    // 2. Get the previous xref position from the original document
    final prevXref = reader.getLastXrefPosition();

    // 3. Write only MODIFIED objects
    for (final ref in xrefTable.references) {
      // Check if info is modified
      if (_info != null && _info!.getPdfObject().isModified()) {
        // Info will be picked up by checking modified refs?
        // Actually we need to make sure info is flushed if modified.
        // But for now, simple loop over refs.
      }

      final isNew = ref.getReader() == null;
      final shouldWrite = !ref.isFree() &&
          !ref.checkState(PdfObject.flushed) &&
          (ref.isModified() || isNew);

      if (shouldWrite) {
        final obj = await ref.getRefersTo();
        if (obj != null) {
          await writer.writeObject(obj);
        }
      }
    }

    // 4. Collect modified references
    final modifiedRefs = <PdfIndirectReference>[];
    for (final ref in xrefTable.references) {
      final isNew = ref.getReader() == null;
      if (!ref.isFree() && (ref.isModified() || isNew)) {
        modifiedRefs.add(ref);
      }
    }

    // 5. Write incremental xref table
    final startxref = writer.getPosition();
    writer.writeIncrementalXrefTable(xrefTable, modifiedRefs);

    // 5. Build new trailer with Prev pointer
    final trailer = PdfDictionary();
    trailer.put(PdfName.intern('Size'), PdfNumber.fromInt(xrefTable.size()));
    trailer.put(PdfName.intern('Root'), getCatalog().getPdfObject());
    trailer.put(PdfName.intern('Prev'), PdfNumber.fromInt(prevXref));

    // Add info if loaded/modified - use indirect reference
    if (_info != null) {
      final infoRef = _info!.getPdfObject().getIndirectReference();
      if (infoRef != null) {
        trailer.put(PdfName.info, infoRef);
      }
    }

    // Set IDs in trailer
    final idArray = PdfArray();
    idArray.add(getOriginalDocumentId());
    idArray.add(getModifiedDocumentId());
    trailer.put(PdfName.id, idArray);

    // Update XMP Metadata in Append Mode
    if (await getXmpMetadataBytes() != null) {
      final cat = getCatalog().getPdfObject();
      var xmpStream = await cat.getAsStream(PdfName.metadata);

      if (xmpStream != null && xmpStream.getIndirectReference() != null) {
        xmpStream.setData(_xmpMetadataBytes!);
        if (!xmpStream.isModified()) {
          xmpStream.setModified();
        }
      } else {
        xmpStream = PdfStream();
        xmpStream.setData(_xmpMetadataBytes!);
        xmpStream.put(PdfName.type, PdfName.metadata);
        xmpStream.put(PdfName.subtype, PdfName.xml);
        xmpStream.makeIndirect(this);
        cat.put(PdfName.metadata, xmpStream);
      }
    }

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
class FingerPrint {
  bool _fingerPrintEnabled = true;

  /// Default constructor.
  FingerPrint();

  /// This method is used to disable  fingerprint.
  void disableFingerPrint() {
    _fingerPrintEnabled = false;
  }

  /// This method is used to check  fingerprint state.
  bool isFingerPrintEnabled() {
    return _fingerPrintEnabled;
  }
}
