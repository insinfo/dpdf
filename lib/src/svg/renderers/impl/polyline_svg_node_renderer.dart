import 'dart:math' as math;

import 'package:dpdf/src/kernel/geom/point.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_dimension_parsing_utils.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/marker_capable.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_css_utils.dart';

/// Renderizador de `<polyline>`, e base de `<polygon>`.
class PolylineSvgNodeRenderer extends AbstractSvgNodeRenderer
    implements MarkerCapable {
  final List<Point> points = [];

  /// Lê o atributo `points`. Uma coordenada solta no fim é descartada em vez
  /// de abortar: os agentes de usuário desenham o prefixo válido.
  void setPoints(String? pointsAttribute) {
    points.clear();
    if (pointsAttribute == null) return;
    final values = SvgCssUtils.splitValueList(pointsAttribute);
    for (var i = 0; i + 1 < values.length; i += 2) {
      final x = _parse(values[i]);
      final y = _parse(values[i + 1]);
      if (x == null || y == null) return;
      points.add(Point(x, y));
    }
  }

  static double? _parse(String value) {
    try {
      return CssDimensionParsingUtils.parseAbsoluteLength(value);
    } catch (_) {
      return null;
    }
  }

  /// `<polygon>` difere apenas por fechar o contorno.
  bool get closesPath => false;

  @override
  List<SvgMarkerVertex> markerVertices(SvgDrawContext context) {
    setPoints(getAttribute(SvgAttributes.POINTS));
    if (points.length < 2) return const [];
    double angle(int from, int to) => math.atan2(
        points[to].getY() - points[from].getY(),
        points[to].getX() - points[from].getX());
    if (closesPath) {
      final result = <SvgMarkerVertex>[];
      for (var i = 0; i < points.length; i++) {
        result.add(SvgMarkerVertex(
            points[i].getX(),
            points[i].getY(),
            angle((i - 1 + points.length) % points.length, i),
            angle(i, (i + 1) % points.length),
            isStart: i == 0));
      }
      // Um subcaminho fechado possui marker-start e marker-end no mesmo ponto.
      result.add(SvgMarkerVertex(result.first.x, result.first.y,
          result.first.incomingAngle, result.first.outgoingAngle,
          isEnd: true));
      return result;
    }
    return [
      SvgMarkerVertex(
          points.first.getX(), points.first.getY(), angle(0, 1), angle(0, 1),
          isStart: true),
      for (var i = 1; i + 1 < points.length; i++)
        SvgMarkerVertex(points[i].getX(), points[i].getY(), angle(i - 1, i),
            angle(i, i + 1)),
      SvgMarkerVertex(
          points.last.getX(),
          points.last.getY(),
          angle(points.length - 2, points.length - 1),
          angle(points.length - 2, points.length - 1),
          isEnd: true),
    ];
  }

  @override
  Future<void> doDraw(SvgDrawContext context) async {
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
  Rectangle? getObjectBoundingBox(SvgDrawContext context) {
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
    return Rectangle(minX, minY, maxX - minX, maxY - minY);
  }

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = PolylineSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
