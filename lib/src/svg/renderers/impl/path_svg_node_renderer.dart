import 'dart:math' as math;

import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/marker_capable.dart';
import 'package:dpdf/src/svg/renderers/path/svg_path_parser.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Renderizador de `<path>`.
class PathSvgNodeRenderer extends AbstractSvgNodeRenderer
    implements MarkerCapable {
  /// O `d` não admite unidades nem percentuais, só números em unidades de
  /// usuário. Ainda assim a escala é obtida do próprio contexto, medindo
  /// quanto vale uma unidade, para acompanhar a mesma conversão px→pt que os
  /// demais atributos sofrem.
  List<SvgPathSegment> _segments(SvgDrawContext context) {
    return SvgPathParser.parse(getAttribute(SvgAttributes.D),
        unitScale: parseHorizontalLength('1', context));
  }

  @override
  Future<void> doDraw(SvgDrawContext context) async {
    final canvas = context.getCurrentCanvas();
    for (final segment in _segments(context)) {
      final c = segment.coordinates;
      switch (segment.op) {
        case SvgPathOp.moveTo:
          canvas.moveTo(c[0], c[1]);
          break;
        case SvgPathOp.lineTo:
          canvas.lineTo(c[0], c[1]);
          break;
        case SvgPathOp.curveTo:
          canvas.curveTo(c[0], c[1], c[2], c[3], c[4], c[5]);
          break;
        case SvgPathOp.close:
          canvas.closePath();
          break;
      }
    }
  }

  @override
  List<SvgMarkerVertex> markerVertices(SvgDrawContext context) {
    final result = <_PathMarkerVertex>[];
    _PathMarkerVertex? current;
    _PathMarkerVertex? start;

    void finishOpen() {
      if (current != null) current!.isEnd = true;
      current = null;
      start = null;
    }

    double angle(double x1, double y1, double x2, double y2,
            [double? fallback]) =>
        x1 == x2 && y1 == y2 ? (fallback ?? 0) : math.atan2(y2 - y1, x2 - x1);

    for (final segment in _segments(context)) {
      final c = segment.coordinates;
      switch (segment.op) {
        case SvgPathOp.moveTo:
          finishOpen();
          current = _PathMarkerVertex(c[0], c[1])..isStart = true;
          start = current;
          result.add(current!);
        case SvgPathOp.lineTo:
          if (current == null) continue;
          final direction =
              angle(current!.x, current!.y, c[0], c[1], current!.incomingAngle);
          current!.outgoingAngle = direction;
          current = _PathMarkerVertex(c[0], c[1])
            ..incomingAngle = direction
            ..outgoingAngle = direction;
          result.add(current!);
        case SvgPathOp.curveTo:
          if (current == null) continue;
          final outgoing = angle(current!.x, current!.y, c[0], c[1],
              angle(current!.x, current!.y, c[4], c[5]));
          final incoming = angle(c[2], c[3], c[4], c[5], outgoing);
          current!.outgoingAngle = outgoing;
          current = _PathMarkerVertex(c[4], c[5])
            ..incomingAngle = incoming
            ..outgoingAngle = incoming;
          result.add(current!);
        case SvgPathOp.close:
          if (current == null || start == null) continue;
          final closing = angle(current!.x, current!.y, start!.x, start!.y,
              current!.incomingAngle);
          current!.outgoingAngle = closing;
          start!.incomingAngle = closing;
          result.add(_PathMarkerVertex(start!.x, start!.y)
            ..incomingAngle = start!.incomingAngle
            ..outgoingAngle = start!.outgoingAngle
            ..isEnd = true);
          current = null;
          start = null;
      }
    }
    finishOpen();
    return [for (final vertex in result) vertex.freeze()];
  }

  /// Caixa envolvente dos pontos de controle: é um limite superior da caixa
  /// real da curva, suficiente para o uso a que serve (posicionar servidores
  /// de pintura) e sem o custo de resolver as raízes de cada Bézier.
  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) {
    double? minX, minY, maxX, maxY;
    for (final segment in _segments(context)) {
      for (var i = 0; i + 1 < segment.coordinates.length; i += 2) {
        final x = segment.coordinates[i];
        final y = segment.coordinates[i + 1];
        minX = minX == null || x < minX ? x : minX;
        maxX = maxX == null || x > maxX ? x : maxX;
        minY = minY == null || y < minY ? y : minY;
        maxY = maxY == null || y > maxY ? y : maxY;
      }
    }
    if (minX == null) return null;
    return Rectangle(minX, minY!, maxX! - minX, maxY! - minY);
  }

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = PathSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}

class _PathMarkerVertex {
  final double x, y;
  double incomingAngle = 0;
  double outgoingAngle = 0;
  bool isStart = false;
  bool isEnd = false;

  _PathMarkerVertex(this.x, this.y);

  SvgMarkerVertex freeze() =>
      SvgMarkerVertex(x, y, incomingAngle, outgoingAngle,
          isStart: isStart, isEnd: isEnd);
}
