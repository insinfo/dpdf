import 'package:dpdf/src/layout/root_element.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/layout/renderer/document_renderer.dart';
import 'package:dpdf/src/layout/renderer/root_renderer.dart';
import 'package:dpdf/src/kernel/font/pdf_font_factory.dart';
import 'package:dpdf/src/io/font/constants/standard_fonts.dart';
import 'package:dpdf/src/layout/properties/property.dart';

class Document extends RootElement<Document> {
  Document(PdfDocument pdfDocument, [PageSize? pageSize]) : super(pdfDocument) {
    if (pageSize != null) {
      pdfDocument.configureDefaultPageExtent(pageSize);
    }
    setProperty(
        Property.FONT, PdfFontFactory.createFont(StandardFonts.HELVETICA));
  }

  @override
  RootRenderer ensureRootRendererNotNull() {
    rootRenderer ??= DocumentRenderer(this);
    return rootRenderer!;
  }

  /// Enables margin collapsing (CSS 2.1, 8.3.1) for the whole document.
  Document setCollapsingMargins(bool collapsingMargins) {
    setProperty(Property.COLLAPSING_MARGINS, collapsingMargins);
    return this;
  }

  /// Sets the page margins used to compute the usable area of every page.
  Document setDocumentMargins(
      double top, double right, double bottom, double left) {
    setMargins(top, right, bottom, left);
    return this;
  }

  @override
  Future<void> closeRootRenderer() async {
    if (rootRenderer != null) {
      await (rootRenderer as DocumentRenderer).close();
    }
  }
}
