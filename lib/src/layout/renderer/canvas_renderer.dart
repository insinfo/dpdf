import 'package:dpdf/src/layout/renderer/root_renderer.dart';
import 'package:dpdf/src/layout/canvas.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/layout/root_layout_area.dart';

/// Places children in the fixed rectangle supplied by a canvas.
class CanvasRenderer extends RootRenderer {
  final Canvas canvas;

  CanvasRenderer(this.canvas, [bool immediateFlush = true]) : super(canvas) {
    this.immediateFlush = immediateFlush;
  }

  @override
  Future<void> addChild(Renderer renderer) async {
    final area = currentArea ?? await updateCurrentArea(null);
    if (area == null) {
      throw StateError('Canvas placement requires a usable rectangle.');
    }
    renderer.setParent(this);
    final result = renderer.layout(LayoutContext(area.clone()));
    if (result == null || result.getStatus() != LayoutResult.FULL) {
      throw StateError('The canvas rectangle cannot contain this child.');
    }
    if (immediateFlush) {
      await flushSingleRenderer(renderer);
    } else {
      await super.addChild(renderer);
    }
    final occupied = result.getOccupiedArea();
    if (occupied != null) {
      final remaining =
          area.getBBox().getHeight() - occupied.getBBox().getHeight();
      area.getBBox().setHeight(remaining < 0 ? 0 : remaining);
    }
  }

  @override
  Future<void> flushSingleRenderer(Renderer renderer) => renderer
      .draw(DrawContext(canvas.getPdfDocument(), canvas.getPdfCanvas(), false));

  @override
  Future<LayoutArea?> updateCurrentArea(LayoutResult? overflowResult) async {
    if (overflowResult != null) return null;
    return currentArea ??= RootLayoutArea(
      canvas.getIsCanvasOfPage() && canvas.pageAt() != null
          ? canvas.getPdfDocument().pageOrdinal(canvas.pageAt()!)
          : 0,
      canvas.getRootArea()!.clone(),
    );
  }

  @override
  LayoutResult layout(LayoutContext context) =>
      LayoutResult(LayoutResult.FULL, context.getArea(), null, null);

  @override
  Renderer getNextRenderer() => CanvasRenderer(canvas, immediateFlush);
}
