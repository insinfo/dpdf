import 'package:dpdf/src/layout/root_element.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/layout/renderer/document_renderer.dart';
import 'package:dpdf/src/layout/renderer/root_renderer.dart';

class Document extends RootElement<Document> {
  Document(PdfDocument pdfDocument, [PageSize? pageSize]) : super(pdfDocument) {
    if (pageSize != null) {
      // TODO: Set default page size properties
    }
  }

  @override
  RootRenderer ensureRootRendererNotNull() {
    if (rootRenderer == null) {
      rootRenderer = DocumentRenderer(this);
    }
    return rootRenderer!;
  }

  @override
  void close() {
    if (rootRenderer != null) {
      (rootRenderer as DocumentRenderer).close();
    }
  }
}
