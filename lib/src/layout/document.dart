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
      pdfDocument.setDefaultPageSize(pageSize);
    }
    setProperty(
        Property.FONT, PdfFontFactory.createFont(StandardFonts.HELVETICA));
  }

  @override
  RootRenderer ensureRootRendererNotNull() {
    if (rootRenderer == null) {
      rootRenderer = DocumentRenderer(this);
    }
    return rootRenderer!;
  }

  @override
  Future<void> close() async {
    if (rootRenderer != null) {
      await (rootRenderer as DocumentRenderer).close();
    }
  }
}
