import 'package:dpdf/src/kernel/geom/point.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_dimension_parsing_utils.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_css_utils.dart';

/// Renderizador de `<polyline>`, e base de `<polygon>`.
class CraftPolylineSvgNodeRenderer extends CraftAbstractSvgNodeRenderer {
  final List<CraftPoint> points = [];

  /// Lê o atributo `points`. Uma coordenada solta no fim é descartada em vez
  /// de abortar: os agentes de usuário desenham o prefixo válido.
  void setPoints(String? pointsAttribute) {
    points.clear();
    if (pointsAttribute == null) return;
    final values = CraftSvgCssUtils.splitValueList(pointsAttribute);
    for (var i = 0; i + 1 < values.length; i += 2) {
      final x = _parse(values[i]);
      final y = _parse(values[i + 1]);
      if (x == null || y == null) return;
      points.add(CraftPoint(x, y));
    }
  }

  static double? _parse(String value) {
    try {
      return CraftCssDimensionParsingUtils.parseAbsoluteLength(value);
    } catch (_) {
      return null;
    }
  }

  /// `<polygon>` difere apenas por fechar o contorno.
  bool get closesPath => false;

  @override
  Future<void> doDraw(CraftSvgDrawContext context) async {
    setPoints(getAttribute(SvgAttributes.POINTS));
    if (points.isEmpty) return;
    final canvas = context.getCurrentCanvas();
    canvas.moveTo(points.first.getX(), points.first.getY());
    for (final point in points.skip(1)) {
      canvas.lineTo(point.getX(), point.getY());
    }
    if (closesPath && points.length > 1) canvas.closePath();
  }

  @override
  CraftRectangle? getObjectBoundingBox(CraftSvgDrawContext context) {
    setPoints(getAttribute(SvgAttributes.POINTS));
    if (points.length < 2) return null;
    var minX = points.first.getX();
    var maxX = minX;
    var minY = points.first.getY();
    var maxY = minY;
    for (final point in points.skip(1)) {
      if (point.getX() < minX) minX = point.getX();
      if (point.getX() > maxX) maxX = point.getX();
      if (point.getY() < minY) minY = point.getY();
      if (point.getY() > maxY) maxY = point.getY();
    }
    return CraftRectangle(minX, minY, maxX - minX, maxY - minY);
  }

  @override
  CraftSvgNodeRenderer createDeepCopy() {
    final copy = CraftPolylineSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
