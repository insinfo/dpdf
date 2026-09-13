import 'package:dpdf/src/layout/document.dart';
import 'package:dpdf/src/layout/element/area_break.dart';
import 'package:dpdf/src/layout/properties/area_break_type.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/renderer/root_renderer.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/pdf_page.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/kernel/geom/page_size.dart';

class DocumentRenderer extends RootRenderer {
  final Document document;
  int currentPageNumber = 0;

  /// Page size used by [updateCurrentArea] for the next page it creates.
  PageSize? nextPageSize;

  DocumentRenderer(this.document) : super(document);

  @override
  Future<void> close() async {
    // flush
    await super.close();
  }

  @override
  Future<void> addChild(Renderer renderer) async {
    renderer.setParent(this);

    if (renderer is AbstractRenderer && renderer.isOutOfFlow()) {
      await _addOutOfFlow(renderer);
      return;
    }

    // While we have content to place
    Renderer? currentRenderer = renderer;
    bool areaIsFresh = false;
    while (currentRenderer != null) {
      if (currentArea == null) {
        await updateCurrentArea(null);
        areaIsFresh = true;
      }

      LayoutResult? result =
          currentRenderer.layout(LayoutContext(currentArea!.clone()));

      if (result == null) break;

      if (result.getStatus() == LayoutResult.FULL) {
        if (result.getOccupiedArea() != null) {
          await _draw(currentRenderer, result.getOccupiedArea()!.getBBox());
          _consume(result.getOccupiedArea()!.getBBox().getHeight());
        }
        currentRenderer = null; // Done
      } else if (result.getStatus() == LayoutResult.PARTIAL) {
        if (result.getSplitRenderer() != null &&
            result.getOccupiedArea() != null) {
          await _draw(
              result.getSplitRenderer()!, result.getOccupiedArea()!.getBBox());
        }
        currentRenderer = result.getOverflowRenderer();
        await _startNewArea(result.getAreaBreak());
        areaIsFresh = true;
      } else {
        // NOTHING
        final AreaBreak? areaBreak = result.getAreaBreak();
        if (areaBreak != null) {
          await _startNewArea(areaBreak);
          currentRenderer = result.getOverflowRenderer();
          areaIsFresh = true;
          continue;
        }
        if (areaIsFresh) {
          // Nothing fits even on a brand new area: force the placement so the
          // content is not silently dropped.
          currentRenderer.setProperty(Property.FORCED_PLACEMENT, true);
          final forced =
              currentRenderer.layout(LayoutContext(currentArea!.clone()));
          if (forced != null && forced.getOccupiedArea() != null) {
            await _draw(currentRenderer, forced.getOccupiedArea()!.getBBox());
            _consume(forced.getOccupiedArea()!.getBBox().getHeight());
          }
          currentRenderer = null;
        } else {
          await _startNewArea(null);
          areaIsFresh = true;
        }
      }
    }
  }

  Future<void> _addOutOfFlow(AbstractRenderer renderer) async {
    final int? requestedPage = renderer.getProperty<int>(Property.PAGE_NUMBER);
    if (requestedPage != null && requestedPage > 0) {
      while (document.pdfDocument.pageTotal() < requestedPage) {
        await updateCurrentArea(null);
      }
      if (currentArea == null) {
        await updateCurrentArea(null);
      }
      final page = await document.pdfDocument.pageAt(requestedPage);
      final bounds = page != null
          ? await page.mediaBounds()
          : currentArea!.getBBox().clone();
      final result = renderer
          .layout(LayoutContext(LayoutArea(requestedPage, bounds.clone())));
      if (result != null && result.getOccupiedArea() != null) {
        await _draw(
            renderer, result.getOccupiedArea()!.getBBox(), requestedPage);
      }
      return;
    }
    if (currentArea == null) {
      await updateCurrentArea(null);
    }
    final result = renderer.layout(LayoutContext(currentArea!.clone()));
    if (result != null && result.getOccupiedArea() != null) {
      await _draw(renderer, result.getOccupiedArea()!.getBBox());
    }
  }

  void _consume(double height) {
    if (currentArea == null) return;
    final box = currentArea!.getBBox();
    final remaining = box.getHeight() - height;
    box.setHeight(remaining < 0 ? 0 : remaining);
  }

  /// Starts a new area, honouring an explicit [AreaBreak] when present.
  Future<void> _startNewArea(AreaBreak? areaBreak) async {
    if (areaBreak != null) {
      nextPageSize = areaBreak.getPageSize();
      if (areaBreak.getAreaBreakType() == AreaBreakType.LAST_PAGE) {
        final total = document.pdfDocument.pageTotal();
        if (total > 0) {
          currentPageNumber = total;
          final page = await document.pdfDocument.pageAt(total);
          if (page != null) {
            currentArea =
                LayoutArea(total, await _usableArea(await page.mediaBounds()));
            return;
          }
        }
      }
    }
    currentArea = null;
  }

  Future<Rectangle> _usableArea(Rectangle pageSize) async {
    final double width = pageSize.getWidth();
    double top = _margin(Property.MARGIN_TOP, width);
    double bottom = _margin(Property.MARGIN_BOTTOM, width);
    double left = _margin(Property.MARGIN_LEFT, width);
    double right = _margin(Property.MARGIN_RIGHT, width);
    return Rectangle(pageSize.getX() + left, pageSize.getY() + bottom,
        width - left - right, pageSize.getHeight() - top - bottom);
  }

  double _margin(int property, double parentWidth) {
    final value = document.getProperty<Object>(property);
    if (value is num) return value.toDouble();
    if (value is UnitValue) {
      if (value.isPointValue()) return value.getValue();
      if (value.isPercentValue()) return value.getValue() * parentWidth / 100.0;
    }
    return 36;
  }

  @override
  Future<LayoutArea?> updateCurrentArea(LayoutResult? overflowResult) async {
    PdfPage page =
        await document.pdfDocument.appendBlankPage(nextPageSize ?? PageSize.A4);
    nextPageSize = null;
    currentPageNumber = document.pdfDocument.pageTotal();
    Rectangle pageSize = await page.mediaBounds();
    currentArea = LayoutArea(currentPageNumber, await _usableArea(pageSize));
    return currentArea;
  }

  @override
  Future<void> flushSingleRenderer(Renderer resultRenderer) async {
    if (resultRenderer.getOccupiedArea() != null) {
      await _draw(resultRenderer, resultRenderer.getOccupiedArea()!.getBBox(),
          resultRenderer.getOccupiedArea()!.pageOrdinal());
    }
  }

  Future<void> _draw(Renderer renderer, Rectangle areaBox,
      [int? pageNumber]) async {
    int pNum = pageNumber ?? currentPageNumber;
    PdfPage? page = await document.pdfDocument.pageAt(pNum);
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
