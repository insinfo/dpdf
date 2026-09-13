import 'dart:math' as math;

import 'package:dpdf/src/svg/renderers/path/svg_path_parser.dart';

/// Um ponto sobre um caminho, com a direção da tangente naquele ponto.
class SvgPathPoint {
  final double x;
  final double y;

  /// Ângulo da tangente em radianos, medido no sentido horário porque o eixo
  /// Y do SVG cresce para baixo.
  final double angle;

  const SvgPathPoint(this.x, this.y, this.angle);
}

/// Caminho achatado em uma polilinha, com comprimentos acumulados.
///
/// É a forma em que `<textPath>` precisa do caminho: posicionar um glifo
/// exige converter distância percorrida em ponto e tangente, o que a lista de
/// segmentos de Bézier não oferece diretamente.
class SvgFlattenedPath {
  final List<double> _x;
  final List<double> _y;
  final List<double> _cumulative;

  SvgFlattenedPath._(this._x, this._y, this._cumulative);

  /// Comprimento total do caminho.
  double get length => _cumulative.isEmpty ? 0 : _cumulative.last;

  /// Se o caminho tem geometria utilizável.
  bool get isEmpty => _x.length < 2 || length <= 0;

  /// Achata [segments], subdividindo cada cúbica proporcionalmente ao
  /// comprimento do seu polígono de controle.
  ///
  /// Subcaminhos separados por um `moveTo` são concatenados: a especificação
  /// trata o caminho referenciado por `<textPath>` como uma única trilha.
  factory SvgFlattenedPath.fromSegments(List<SvgPathSegment> segments) {
    final xs = <double>[];
    final ys = <double>[];
    double? startX, startY;

    void add(double x, double y) {
      if (xs.isNotEmpty && xs.last == x && ys.last == y) return;
      xs.add(x);
      ys.add(y);
    }

    for (final segment in segments) {
      final c = segment.coordinates;
      switch (segment.op) {
        case SvgPathOp.moveTo:
          startX = c[0];
          startY = c[1];
          add(c[0], c[1]);
        case SvgPathOp.lineTo:
          add(c[0], c[1]);
        case SvgPathOp.curveTo:
          if (xs.isEmpty) {
            add(c[4], c[5]);
            break;
          }
          final x0 = xs.last, y0 = ys.last;
          final polygon = _distance(x0, y0, c[0], c[1]) +
              _distance(c[0], c[1], c[2], c[3]) +
              _distance(c[2], c[3], c[4], c[5]);
          final steps = polygon.isFinite
              ? math.max(4, math.min(64, (polygon / 1.5).ceil()))
              : 16;
          for (var step = 1; step <= steps; step++) {
            final t = step / steps;
            final u = 1 - t;
            final bx = u * u * u * x0 +
                3 * u * u * t * c[0] +
                3 * u * t * t * c[2] +
                t * t * t * c[4];
            final by = u * u * u * y0 +
                3 * u * u * t * c[1] +
                3 * u * t * t * c[3] +
                t * t * t * c[5];
            add(bx, by);
          }
        case SvgPathOp.close:
          if (startX != null && startY != null) add(startX, startY);
      }
    }

    final cumulative = <double>[];
    var total = 0.0;
    for (var i = 0; i < xs.length; i++) {
      if (i > 0) total += _distance(xs[i - 1], ys[i - 1], xs[i], ys[i]);
      cumulative.add(total);
    }
    return SvgFlattenedPath._(xs, ys, cumulative);
  }

  /// Ponto e tangente à distância [distance] do início do caminho.
  ///
  /// Devolve `null` fora do intervalo `[0, length]`, que é onde a §10.13.2
  /// manda não renderizar o glifo.
  SvgPathPoint? pointAt(double distance) {
    if (isEmpty || distance < 0 || distance > length) return null;
    var low = 0;
    var high = _cumulative.length - 1;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_cumulative[middle] < distance) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final index = low == 0 ? 1 : low;
    final segmentLength = _cumulative[index] - _cumulative[index - 1];
    final ratio = segmentLength <= 0
        ? 0.0
        : (distance - _cumulative[index - 1]) / segmentLength;
    final dx = _x[index] - _x[index - 1];
    final dy = _y[index] - _y[index - 1];
    return SvgPathPoint(_x[index - 1] + dx * ratio, _y[index - 1] + dy * ratio,
        math.atan2(dy, dx));
  }

  static double _distance(double x1, double y1, double x2, double y2) =>
      math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
}
