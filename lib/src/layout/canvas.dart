import 'package:pdfcraft/src/layout/root_element.dart';
import 'package:pdfcraft/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:pdfcraft/src/kernel/geom/rectangle.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_page.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/layout/renderer/root_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/canvas_renderer.dart';

class CraftCanvas extends CraftRootElement<CraftCanvas> {
  CraftPdfCanvas? pdfCanvas;
  CraftRectangle? rootArea;
  CraftPdfPage? page;
  bool isCanvasOfPage = false;

  CraftCanvas(CraftPdfCanvas pdfCanvas, CraftRectangle rootArea)
      : super(pdfCanvas.getDocument()!) {
    this.pdfCanvas = pdfCanvas;
    this.rootArea = rootArea;
    this.immediateFlush = true;
  }

  // TODO: Add other constructors and methods

  @override
  CraftRootRenderer ensureRootRendererNotNull() {
    if (rootRenderer == null) {
      rootRenderer = CraftCanvasRenderer(this);
    }
    return rootRenderer!;
  }

  static Future<CraftCanvas> fromPage(
      CraftPdfPage page, CraftRectangle? rootArea) async {
    final pdfCanvas = await CraftPdfCanvas.fromPage(page);
    return CraftCanvas(pdfCanvas, rootArea ?? (await page.mediaBounds()));
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

  CraftPdfDocument getPdfDocument() {
    return pdfDocument;
  }

  CraftPdfCanvas getPdfCanvas() {
    return pdfCanvas!;
  }

  CraftPdfPage? pageAt() {
    return page;
  }

  bool getIsCanvasOfPage() {
    return isCanvasOfPage;
  }

  CraftRectangle? getRootArea() {
    return rootArea;
  }
}
