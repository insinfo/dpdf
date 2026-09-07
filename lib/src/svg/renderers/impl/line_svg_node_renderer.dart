import 'dart:math' as math;

import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Renderizador de `<line>`.
class CraftLineSvgNodeRenderer extends CraftAbstractSvgNodeRenderer {
  double x1 = 0;
  double y1 = 0;
  double x2 = 0;
  double y2 = 0;

  void _setParameters(CraftSvgDrawContext context) {
    x1 = parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.X1, '0'), context);
    y1 = parseVerticalLength(
        getAttributeOrDefault(SvgAttributes.Y1, '0'), context);
    x2 = parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.X2, '0'), context);
    y2 = parseVerticalLength(
        getAttributeOrDefault(SvgAttributes.Y2, '0'), context);
  }

  @override
  Future<void> doDraw(CraftSvgDrawContext context) async {
    _setParameters(context);
    context.getCurrentCanvas().moveTo(x1, y1).lineTo(x2, y2);
  }

  /// Uma reta não tem área, então `fill` nunca se aplica a ela.
  @override
  bool canElementFill() => false;

  @override
  CraftRectangle? getObjectBoundingBox(CraftSvgDrawContext context) {
    _setParameters(context);
    return CraftRectangle(
        math.min(x1, x2), math.min(y1, y2), (x1 - x2).abs(), (y1 - y2).abs());
  }

  @override
  CraftSvgNodeRenderer createDeepCopy() {
    final copy = CraftLineSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
