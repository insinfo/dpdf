import 'package:dpdf/src/layout/root_element.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/pdf_page.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/layout/renderer/root_renderer.dart';
import 'package:dpdf/src/layout/renderer/canvas_renderer.dart';

class Canvas extends RootElement<Canvas> {
  PdfCanvas? pdfCanvas;
  Rectangle? rootArea;
  PdfPage? page;
  bool isCanvasOfPage = false;

  Canvas(PdfCanvas pdfCanvas, Rectangle rootArea)
      : super(pdfCanvas.getDocument()!) {
    this.pdfCanvas = pdfCanvas;
    this.rootArea = rootArea;
    this.immediateFlush = true;
  }

  // TODO: Add other constructors and methods

  @override
  RootRenderer ensureRootRendererNotNull() {
    if (rootRenderer == null) {
      rootRenderer = CanvasRenderer(this);
    }
    return rootRenderer!;
  }

  static Future<Canvas> fromPage(PdfPage page, Rectangle? rootArea) async {
    final pdfCanvas = await PdfCanvas.fromPage(page);
    return Canvas(pdfCanvas, rootArea ?? (await page.getMediaBox()));
  }

  Future<void> flush() async {
    await ensureRootRendererNotNull().flush();
  }

  @override
  Future<void> close() async {
    if (rootRenderer != null) {
      // (rootRenderer as CanvasRenderer).close(); // RootRenderer has close()
      await rootRenderer!.close();
    }
  }

  PdfDocument getPdfDocument() {
    return pdfDocument;
  }

  PdfCanvas getPdfCanvas() {
    return pdfCanvas!;
  }

  PdfPage? getPage() {
    return page;
  }

  bool getIsCanvasOfPage() {
    return isCanvasOfPage;
  }

  Rectangle? getRootArea() {
    return rootArea;
  }
}
