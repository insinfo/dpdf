import 'pdf_object.dart';
import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_writer.dart';
import 'pdf_reader.dart';
import 'pdf_catalog.dart';
import 'pdf_xref_table.dart';
import 'pdf_version.dart';
import 'pdf_page.dart';
import '../geom/page_size.dart';
import '../exceptions/pdf_exception.dart';

/// Main enter point to work with PDF document.
class PdfDocument {
  final PdfXrefTable xref = PdfXrefTable();

  PdfWriter? _writer;
  PdfReader? _reader;
  PdfCatalog? _catalog;
  PdfDictionary? _trailer;
  PdfVersion _pdfVersion = PdfVersion.PDF_1_7;
  PageSize _defaultPageSize = PageSize.defaultSize;

  bool _closed = false;

  PdfDocument._({PdfWriter? writer}) : _writer = writer {
    if (_writer != null) {
      _writer!.document = this;
    }
  }

  /// Creates a new PDF document for writing.
  static Future<PdfDocument> create(PdfWriter writer) async {
    final doc = PdfDocument._(writer: writer);
    await doc._open();
    return doc;
  }

  /// Opens an existing PDF document for reading.
  static Future<PdfDocument> open(PdfReader reader, {PdfWriter? writer}) async {
    final doc = PdfDocument._(writer: writer);
    doc._reader = reader;
    reader.document = doc;
    await doc._openFromReader();
    return doc;
  }

  Future<void> _openFromReader() async {
    if (_reader == null) return;
    await _reader!.read();
    _trailer = _reader!.getTrailer();
    final catalogDict = await _reader!.getCatalog();
    if (catalogDict != null) {
      _catalog = PdfCatalog(catalogDict);
      await _catalog!.init();
    }
  }

  Future<void> _open() async {
    _trailer = PdfDictionary();
    _catalog = PdfCatalog(PdfDictionary());
    _catalog!.getPdfObject().makeIndirect(this);
    await _catalog!.init();
    _trailer!
        .put(PdfName.root, _catalog!.getPdfObject().getIndirectReference()!);
    // TODO: Initial setup (info, ID, etc)
  }

  PdfCatalog getCatalog() {
    _checkClosingStatus();
    return _catalog!;
  }

  PdfDictionary getTrailer() => _trailer!;

  Future<void> addNewPage([PageSize? pageSize]) async {
    _checkClosingStatus();
    final size = pageSize ?? _defaultPageSize;
    final pageDict = PdfDictionary();
    pageDict.makeIndirect(this);
    pageDict.put(PdfName.type, PdfName.page);
    pageDict.put(PdfName.mediaBox, size.toPdfArray());

    final page = PdfPage(pageDict);
    await _catalog!.getPageTree().addPage(page);
  }

  int getNumberOfPages() {
    _checkClosingStatus();
    return _catalog!.getPageTree().getNumberOfPages();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    if (_writer != null) {
      _writer!.writeHeader();
      // Write all indirect objects
      for (final ref in xref.references) {
        if (!ref.isFree()) {
          final obj = await ref.getRefersTo();
          if (obj != null) {
            await _writer!.writeObject(obj);
          }
        }
      }
      final startxref = _writer!.getPosition();
      _writer!.writeXrefTable(xref);
      await _writer!.writeTrailer(_trailer!, startxref);
      _writer!.writeEOF();
      _writer!.flush();
      await _writer!.close();
    }

    if (_reader != null) {
      await _reader!.close();
    }
  }

  void _checkClosingStatus() {
    if (_closed) {
      throw PdfException(
          'Document was closed. It is impossible to execute action.');
    }
  }

  PdfIndirectReference createNextIndirectReference() {
    final ref = PdfIndirectReference(xref.size())..setDocument(this);
    xref.add(ref);
    return ref;
  }

  Future<PdfObject?> readObject(PdfIndirectReference ref) async {
    if (_reader != null) {
      return await _reader!.readObject(ref.getObjNumber());
    }
    return null;
  }

  PdfVersion getPdfVersion() => _pdfVersion;
}
