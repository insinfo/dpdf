import 'pdf_name.dart';
import 'pdf_pages.dart';
import 'pdf_page.dart';
import 'pdf_catalog.dart';
import '../exceptions/pdf_exception.dart';
import '../exceptions/kernel_exception_message_constant.dart';

/// Algorithm for construction of PdfPages tree.
class PdfPagesTree {
  final List<PdfPages> _parents = [];
  final List<PdfPage?> _pages = [];
  PdfPages? _root;
  final PdfCatalog _catalog;

  PdfPagesTree(this._catalog);

  /// Initializes the pages tree by reading the tree structure from the catalog.
  Future<void> init() async {
    final catalogDict = _catalog.getPdfObject();
    if (catalogDict.containsKey(PdfName.pages)) {
      final pagesDict = await catalogDict.getAsDictionary(PdfName.pages);
      if (pagesDict == null) {
        throw PdfException(KernelExceptionMessageConstant
            .invalidPageStructurePagesMustBePdfDictionary);
      }
      _root = PdfPages(0, pdfObject: pagesDict);
      await _root!.init();
      _parents.add(_root!);
      final count = _root!.getCount();
      for (var i = 0; i < count; i++) {
        _pages.add(null);
      }
    }
  }

  int getNumberOfPages() {
    return _pages.length;
  }

  Future<PdfPage?> getPage(int pageNum) async {
    if (pageNum < 1 || pageNum > getNumberOfPages()) {
      throw RangeError('Requested page number $pageNum is out of bounds.');
    }
    final index = pageNum - 1;
    var page = _pages[index];
    if (page == null) {
      // TODO: Load page from tree if not loaded
      // This will involve traversing the kids array asynchronously
    }
    return page;
  }

  Future<void> addPage(PdfPage page) async {
    if (_root == null) {
      _root = PdfPages(0);
      await _root!.init();
      _root!.getPdfObject().makeIndirect(
          _catalog.getPdfObject().getIndirectReference()!.getDocument()!);
      _catalog.getPdfObject().put(PdfName.pages, _root!.getPdfObject());
      _parents.add(_root!);
    }
    _root!.addPage(page.getPdfObject());
    _pages.add(page);
    page.parentPages = _root;
  }
}
