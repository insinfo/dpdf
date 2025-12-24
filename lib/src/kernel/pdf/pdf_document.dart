import '../font/pdf_font.dart';
import '../font/pdf_font_factory.dart';
import '../geom/page_size.dart';
import 'pdf_dictionary.dart';
import 'pdf_object.dart';
import 'pdf_reader.dart';
import 'pdf_writer.dart';
import 'pdf_catalog.dart';
import 'pdf_pages_tree.dart';
import 'pdf_xref_table.dart';
import 'pdf_version.dart';
import 'pdf_encryption.dart';
import 'pdf_page.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';

class PdfDocument {
  PdfReader? _reader;
  PdfWriter? _writer;
  PdfXrefTable? _xrefTable;
  PdfCatalog? _catalog;
  PdfPagesTree? _pagesTree;
  PdfEncryption? _encryption;
  PdfVersion? _version;

  bool _closed = false;

  PdfDocument({PdfReader? reader, PdfWriter? writer})
      : _reader = reader,
        _writer = writer {
    _init();
  }

  static Future<PdfDocument> create(PdfWriter writer) async {
    return PdfDocument(writer: writer);
  }

  static Future<PdfDocument> open(PdfReader reader) async {
    await reader.read();
    final doc = PdfDocument(reader: reader);
    final catalogDict = await reader.getCatalog();
    if (catalogDict != null) {
      doc._catalog = PdfCatalog(catalogDict);
      await doc._catalog!.init();
      doc._pagesTree = doc._catalog!.getPageTree();
    }
    return doc;
  }

  void _init() {
    if (_reader != null) {
      _xrefTable = _reader!.xref;
      _version = _reader!.getPdfVersion();
      _reader!.setDocument(this);
    } else {
      _xrefTable = PdfXrefTable();
      _version = PdfVersion.PDF_1_7;
    }
    if (_writer != null) {
      _writer!.document = this;
    }
  }

  PdfReader? getReader() => _reader;
  PdfWriter? getWriter() => _writer;

  PdfCatalog getCatalog() {
    if (_catalog == null) {
      if (_reader != null) {
        // Try to get from reader
      }
      if (_catalog == null) {
        _catalog = PdfCatalog(PdfDictionary());
        _catalog!.getPdfObject().makeIndirect(this);
      }
    }
    return _catalog!;
  }

  void setCatalog(PdfCatalog catalog) {
    _catalog = catalog;
  }

  PdfPagesTree getPagesTree() {
    if (_pagesTree == null) {
      _pagesTree = PdfPagesTree(getCatalog());
    }
    return _pagesTree!;
  }

  PdfXrefTable? getXrefTable() => _xrefTable;

  PdfEncryption? getEncryption() => _encryption;

  PdfVersion? getVersion() => _version;

  bool isClosed() => _closed;

  PdfIndirectReference createNextIndirectReference() {
    final objNr = _xrefTable!.size();
    return _xrefTable!.add(PdfIndirectReference(objNr, 0)..setDocument(this))!;
  }

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

  Future<PdfPage> addNewPage([PageSize? pageSize]) async {
    final page = PdfPage(PdfDictionary());
    page.getPdfObject().makeIndirect(this);
    page.setMediaBox(pageSize ?? PageSize.defaultSize);
    await getPagesTree().addPage(page, this);
    return page;
  }

  Future<PdfPage?> getPage(int pageNumber) async {
    return await getPagesTree().getPage(pageNumber);
  }

  int getNumberOfPages() {
    return getPagesTree().getNumberOfPages();
  }

  Future<void> close() async {
    if (_closed) return;

    if (_writer != null) {
      _writer!.writeHeader();

      // Ensure catalog and pages tree are initialized
      final catalog = getCatalog();
      await getPagesTree(); // ensure initialized? Wait, getPagesTree is sync but we might need more.

      // We should probably flush all objects from xref table
      for (final ref in _xrefTable!.references) {
        if (!ref.isFree()) {
          final obj = await ref.getRefersTo();
          if (obj != null) {
            await _writer!.writeObject(obj);
          }
        }
      }

      final startxref = _writer!.getPosition();
      _writer!.writeXrefTable(_xrefTable!);

      final trailer = PdfDictionary();
      trailer.put(
          PdfName.intern('Size'), PdfNumber.fromInt(_xrefTable!.size()));
      trailer.put(PdfName.intern('Root'), catalog.getPdfObject());

      await _writer!.writeTrailer(trailer, startxref);
      _writer!.writeEOF();
      await _writer!.close();
    }

    _closed = true;
  }

  Future<PdfFont?> getFont(PdfDictionary fontDict) async {
    return await PdfFontFactory.createFontFromDictionary(fontDict);
  }
}
