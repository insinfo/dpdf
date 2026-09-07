import 'package:dpdf/src/layout/root_element.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/layout/renderer/document_renderer.dart';
import 'package:dpdf/src/layout/renderer/root_renderer.dart';
import 'package:dpdf/src/kernel/font/pdf_font_factory.dart';
import 'package:dpdf/src/io/font/constants/standard_fonts.dart';
import 'package:dpdf/src/layout/properties/property.dart';

class CraftDocument extends CraftRootElement<CraftDocument> {
  CraftDocument(CraftPdfDocument pdfDocument, [CraftPageSize? pageSize])
      : super(pdfDocument) {
    if (pageSize != null) {
      pdfDocument.configureDefaultPageExtent(pageSize);
    }
    setProperty(CraftProperty.FONT,
        CraftPdfFontFactory.createFont(CraftStandardFonts.HELVETICA));
  }

  @override
  CraftRootRenderer ensureRootRendererNotNull() {
    if (rootRenderer == null) {
      rootRenderer = CraftDocumentRenderer(this);
    }
    return rootRenderer!;
  }

  @override
  Future<void> close() async {
    if (rootRenderer != null) {
      await (rootRenderer as CraftDocumentRenderer).close();
    }
  }
}
