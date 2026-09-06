import 'package:dpdf/src/layout/document.dart';
import 'package:dpdf/src/layout/renderer/root_renderer.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/pdf_page.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/kernel/geom/page_size.dart';

class DocumentRenderer extends RootRenderer {
  final Document document;
  int currentPageNumber = 0;

  DocumentRenderer(this.document) : super(document);

  @override
  Future<void> close() async {
    // flush
    await super.close();
  }

  @override
  Future<void> addChild(IRenderer renderer) async {
    renderer.setParent(this);

    // While we have content to place
    IRenderer? currentRenderer = renderer;
    while (currentRenderer != null) {
      if (currentArea == null) {
        await updateCurrentArea(null);
      }

      LayoutResult? result =
          currentRenderer.layout(LayoutContext(currentArea!));

      if (result != null) {
        if (result.getStatus() == LayoutResult.FULL) {
          if (result.getOccupiedArea() != null) {
            await _draw(currentRenderer, result.getOccupiedArea()!.getBBox());
            if (currentArea != null && result.getOccupiedArea() != null) {
              currentArea!.getBBox().setHeight(currentArea!.getBBox().getHeight() -
                  result.getOccupiedArea()!.getBBox().getHeight());
            }
          }
          currentRenderer = null; // Done
        } else if (result.getStatus() == LayoutResult.PARTIAL) {
          if (result.getSplitRenderer() != null &&
              result.getOccupiedArea() != null) {
            await _draw(result.getSplitRenderer()!,
                result.getOccupiedArea()!.getBBox());
          }
          currentRenderer = result.getOverflowRenderer();
          currentArea = null; // Need new page
        } else {
          // NOTHING
          // Force to new page if not already there, else error or force placement?
          // For now, simple next page
          if (currentArea != null) {
            // Maybe area too small?
            currentArea = null;
          } else {
            // Should not happen if new page
            break;
          }
        }
      } else {
        break;
      }
    }
  }

  @override
  Future<LayoutArea?> updateCurrentArea(LayoutResult? overflowResult) async {
    PdfPage page = await document.pdfDocument.addNewPage(PageSize.A4);
    currentPageNumber++;
    Rectangle pageSize = await page.getMediaBox();
    // simplified margins
    Rectangle usable =
        Rectangle(36, 36, pageSize.getWidth() - 72, pageSize.getHeight() - 72);
    currentArea = LayoutArea(currentPageNumber, usable);
    return currentArea;
  }

  @override
  Future<void> flushSingleRenderer(IRenderer resultRenderer) async {
    if (resultRenderer.getOccupiedArea() != null) {
      await _draw(resultRenderer, resultRenderer.getOccupiedArea()!.getBBox(),
          resultRenderer.getOccupiedArea()!.getPageNumber());
    }
  }

  Future<void> _draw(IRenderer renderer, Rectangle areaBox,
      [int? pageNumber]) async {
    int pNum = pageNumber ?? currentPageNumber;
    PdfPage? page = await document.pdfDocument.getPage(pNum);
    if (page != null) {
      PdfCanvas canvas = await PdfCanvas.fromPage(page);
      await renderer.draw(DrawContext(document.pdfDocument, canvas));
    }
  }

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    return LayoutResult(LayoutResult.FULL, layoutContext.getArea(), null, null);
  }
}
