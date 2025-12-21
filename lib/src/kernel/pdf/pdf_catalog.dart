import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_object_wrapper.dart';
import 'pdf_pages_tree.dart';
import '../exceptions/pdf_exception.dart';

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
}
