import 'package:dpdf/src/layout/renderer/root_renderer.dart';
import 'package:dpdf/src/layout/canvas.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/layout/root_layout_area.dart';

/// Places children in the fixed rectangle supplied by a canvas.
class CraftCanvasRenderer extends CraftRootRenderer {
  final CraftCanvas canvas;

  CraftCanvasRenderer(this.canvas, [bool immediateFlush = true])
      : super(canvas) {
    this.immediateFlush = immediateFlush;
  }

  @override
  Future<void> addChild(CraftRenderer renderer) async {
    final area = currentArea ?? await updateCurrentArea(null);
    if (area == null) {
      throw StateError('Canvas placement requires a usable rectangle.');
    }
    renderer.setParent(this);
    final result = renderer.layout(CraftLayoutContext(area.clone()));
    if (result == null || result.getStatus() != CraftLayoutResult.FULL) {
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
  Future<void> flushSingleRenderer(CraftRenderer renderer) => renderer.draw(
      CraftDrawContext(canvas.getPdfDocument(), canvas.getPdfCanvas(), false));

  @override
  Future<CraftLayoutArea?> updateCurrentArea(
      CraftLayoutResult? overflowResult) async {
    if (overflowResult != null) return null;
    return currentArea ??= CraftRootLayoutArea(
      canvas.getIsCanvasOfPage() && canvas.pageAt() != null
          ? canvas.getPdfDocument().pageOrdinal(canvas.pageAt()!)
          : 0,
      canvas.getRootArea()!.clone(),
    );
  }

  @override
  CraftLayoutResult layout(CraftLayoutContext context) =>
      CraftLayoutResult(CraftLayoutResult.FULL, context.getArea(), null, null);

  @override
  CraftRenderer getNextRenderer() =>
      CraftCanvasRenderer(canvas, immediateFlush);
}
