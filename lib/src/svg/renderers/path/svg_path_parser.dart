import 'dart:math' as math;

/// Operadores de traçado suportados pelo PDF depois da normalização.
///
/// O `d` do SVG tem vinte formas (absolutas, relativas, taquigrafias, arcos),
/// mas o PDF só conhece quatro. Reduzir tudo a este conjunto no parser mantém
/// os renderizadores triviais e torna o resultado inspecionável em testes.
enum CraftSvgPathOp { moveTo, lineTo, curveTo, close }

/// Um trecho de caminho já em coordenadas absolutas e prontas para o canvas.
class CraftSvgPathSegment {
  final CraftSvgPathOp op;

  /// Pares x/y: vazio em [CraftSvgPathOp.close], dois valores em move/line e
  /// seis (dois controles mais o destino) em curve.
  final List<double> coordinates;

  const CraftSvgPathSegment(this.op, this.coordinates);

  @override
  String toString() => '$op$coordinates';
}

/// Converte o atributo `d` de `<path>` numa lista de segmentos absolutos.
///
/// O iText modela cada operador como uma classe própria; aqui um único
/// autômato resolve o mesmo problema, porque a gramática do caminho é
/// estritamente linear e todo o estado que importa cabe em cinco variáveis
/// (ponto corrente, início do subcaminho e último ponto de controle).
class CraftSvgPathParser {
  CraftSvgPathParser._();

  /// Comandos e números; os números aceitam a notação exponencial e a forma
  /// `.5` que o SVG permite colar sem separador (`1.5.5` são dois números).
  static final RegExp _token = RegExp(
      r'[MmLlHhVvCcSsQqTtAaZz]|[+-]?(?:\d*\.\d+|\d+\.?)(?:[eE][+-]?\d+)?');

  /// [unitScale] converte unidades de usuário do SVG para pontos do PDF; é
  /// aplicada uma única vez, na emissão, para o autômato trabalhar sempre no
  /// espaço em que o arquivo foi escrito.
  ///
  /// Um `d` malformado não interrompe o desenho: devolve-se o que foi
  /// entendido até o erro, como fazem os agentes de usuário.
  static List<CraftSvgPathSegment> parse(String? pathData,
      {double unitScale = 1.0}) {
    final segments = <CraftSvgPathSegment>[];
    if (pathData == null || pathData.trim().isEmpty) return segments;

    final tokens =
        _token.allMatches(pathData).map((match) => match.group(0)!).toList();

    // Ponto corrente, início do subcaminho e controles refletidos por S/T.
    var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
    var cubicX = 0.0, cubicY = 0.0, quadX = 0.0, quadY = 0.0;
    var lastWasCubic = false, lastWasQuad = false;

    String? command;
    var index = 0;

    double? number() {
      if (index >= tokens.length) return null;
      final value = double.tryParse(tokens[index]);
      if (value == null) return null;
      index++;
      return value;
    }

    void emit(CraftSvgPathOp op, List<double> coordinates) {
      segments.add(CraftSvgPathSegment(
          op, coordinates.map((value) => value * unitScale).toList()));
    }

    while (index < tokens.length) {
      final token = tokens[index];
      if (double.tryParse(token) == null) {
        command = token;
        index++;
        // Um `M`/`m` isolado passa a valer como `L`/`l` nas repetições
        // implícitas, conforme a especificação.
        if (command == 'Z' || command == 'z') {
          emit(CraftSvgPathOp.close, const []);
          x = startX;
          y = startY;
          lastWasCubic = false;
          lastWasQuad = false;
          continue;
        }
      } else if (command == null) {
        // Números antes de qualquer comando são lixo: não há como interpretá-los.
        break;
      }

      final current = command!;
      final relative = current == current.toLowerCase();
      final upper = current.toUpperCase();
      final originX = relative ? x : 0.0;
      final originY = relative ? y : 0.0;
      var isCubic = false;
      var isQuad = false;

      switch (upper) {
        case 'M':
          final px = number(), py = number();
          if (px == null || py == null) return segments;
          x = originX + px;
          y = originY + py;
          startX = x;
          startY = y;
          emit(CraftSvgPathOp.moveTo, [x, y]);
          command = relative ? 'l' : 'L';
          break;
        case 'L':
          final px = number(), py = number();
          if (px == null || py == null) return segments;
          x = originX + px;
          y = originY + py;
          emit(CraftSvgPathOp.lineTo, [x, y]);
          break;
        case 'H':
          final px = number();
          if (px == null) return segments;
          x = originX + px;
          emit(CraftSvgPathOp.lineTo, [x, y]);
          break;
        case 'V':
          final py = number();
          if (py == null) return segments;
          y = originY + py;
          emit(CraftSvgPathOp.lineTo, [x, y]);
          break;
        case 'C':
          final x1 = number(), y1 = number();
          final x2 = number(), y2 = number();
          final px = number(), py = number();
          if (px == null || py == null || x1 == null || y1 == null) {
            return segments;
          }
          if (x2 == null || y2 == null) return segments;
          final c1x = originX + x1, c1y = originY + y1;
          final c2x = originX + x2, c2y = originY + y2;
          x = originX + px;
          y = originY + py;
          emit(CraftSvgPathOp.curveTo, [c1x, c1y, c2x, c2y, x, y]);
          cubicX = c2x;
          cubicY = c2y;
          isCubic = true;
          break;
        case 'S':
          final x2 = number(), y2 = number();
          final px = number(), py = number();
          if (x2 == null || y2 == null || px == null || py == null) {
            return segments;
          }
          // Sem cúbica anterior o primeiro controle coincide com o ponto
          // corrente, e não com um reflexo inexistente.
          final c1x = lastWasCubic ? 2 * x - cubicX : x;
          final c1y = lastWasCubic ? 2 * y - cubicY : y;
          final c2x = originX + x2, c2y = originY + y2;
          x = originX + px;
          y = originY + py;
          emit(CraftSvgPathOp.curveTo, [c1x, c1y, c2x, c2y, x, y]);
          cubicX = c2x;
          cubicY = c2y;
          isCubic = true;
          break;
        case 'Q':
          final qx = number(), qy = number();
          final px = number(), py = number();
          if (qx == null || qy == null || px == null || py == null) {
            return segments;
          }
          final controlX = originX + qx, controlY = originY + qy;
          final endX = originX + px, endY = originY + py;
          emit(CraftSvgPathOp.curveTo,
              _quadraticToCubic(x, y, controlX, controlY, endX, endY));
          quadX = controlX;
          quadY = controlY;
          x = endX;
          y = endY;
          isQuad = true;
          break;
        case 'T':
          final px = number(), py = number();
          if (px == null || py == null) return segments;
          final controlX = lastWasQuad ? 2 * x - quadX : x;
          final controlY = lastWasQuad ? 2 * y - quadY : y;
          final endX = originX + px, endY = originY + py;
          emit(CraftSvgPathOp.curveTo,
              _quadraticToCubic(x, y, controlX, controlY, endX, endY));
          quadX = controlX;
          quadY = controlY;
          x = endX;
          y = endY;
          isQuad = true;
          break;
        case 'A':
          final rx = number(), ry = number();
          final rotation = number();
          final largeArc = number(), sweep = number();
          final px = number(), py = number();
          if (rx == null ||
              ry == null ||
              rotation == null ||
              largeArc == null ||
              sweep == null ||
              px == null ||
              py == null) {
            return segments;
          }
          final endX = originX + px, endY = originY + py;
          for (final curve in _arcToCurves(x, y, rx, ry, rotation,
              largeArc != 0, sweep != 0, endX, endY)) {
            emit(CraftSvgPathOp.curveTo, curve);
          }
          x = endX;
          y = endY;
          break;
        default:
          // Comando desconhecido: nada mais pode ser interpretado com segurança.
          return segments;
      }

      lastWasCubic = isCubic;
      lastWasQuad = isQuad;
    }
    return segments;
  }

  /// Eleva uma quadrática ao grau três, única forma de curva que o PDF aceita.
  static List<double> _quadraticToCubic(double x0, double y0, double cx,
      double cy, double x1, double y1) {
    return [
      x0 + 2 / 3 * (cx - x0),
      y0 + 2 / 3 * (cy - y0),
      x1 + 2 / 3 * (cx - x1),
      y1 + 2 / 3 * (cy - y1),
      x1,
      y1,
    ];
  }

  /// Converte o arco elíptico da parametrização por extremos (a do SVG) em
  /// cúbicas de Bézier, seguindo o apêndice F.6 da especificação SVG 1.1.
  static List<List<double>> _arcToCurves(double x1, double y1, double rx,
      double ry, double rotation, bool largeArc, bool sweep, double x2,
      double y2) {
    // Extremos coincidentes anulam o arco; raio nulo degenera em reta. Ambos
    // os casos estão previstos na especificação e não são erro.
    if (x1 == x2 && y1 == y2) return const [];
    if (rx == 0 || ry == 0) {
      return [
        [x1, y1, x2, y2, x2, y2]
      ];
    }
    rx = rx.abs();
    ry = ry.abs();
    final phi = rotation * math.pi / 180.0;
    final cosPhi = math.cos(phi), sinPhi = math.sin(phi);

    final dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
    final x1p = cosPhi * dx + sinPhi * dy;
    final y1p = -sinPhi * dx + cosPhi * dy;

    // Raios menores que a corda são ampliados até caberem, em vez de gerarem
    // uma raiz negativa mais adiante.
    final lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lambda > 1) {
      final enlargement = math.sqrt(lambda);
      rx *= enlargement;
      ry *= enlargement;
    }

    final numerator =
        rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
    final denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
    var center = denominator == 0
        ? 0.0
        : math.sqrt(math.max(0, numerator) / denominator);
    if (largeArc == sweep) center = -center;

    final cxp = center * rx * y1p / ry;
    final cyp = -center * ry * x1p / rx;
    final cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2;
    final cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2;

    final theta1 = math.atan2((y1p - cyp) / ry, (x1p - cxp) / rx);
    final theta2 = math.atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx);
    var delta = theta2 - theta1;
    if (!sweep && delta > 0) {
      delta -= 2 * math.pi;
    } else if (sweep && delta < 0) {
      delta += 2 * math.pi;
    }

    // Uma cúbica só aproxima bem até um quarto de volta; daí a fatia de 90°.
    final count = math.max(1, (delta.abs() / (math.pi / 2)).ceil());
    final step = delta / count;
    final alpha = 4 / 3 * math.tan(step / 4);

    final curves = <List<double>>[];
    var theta = theta1;
    for (var i = 0; i < count; i++) {
      final next = theta + step;
      final start = _ellipsePoint(cx, cy, rx, ry, cosPhi, sinPhi, theta);
      final end = _ellipsePoint(cx, cy, rx, ry, cosPhi, sinPhi, next);
      final startSlope =
          _ellipseSlope(rx, ry, cosPhi, sinPhi, theta);
      final endSlope = _ellipseSlope(rx, ry, cosPhi, sinPhi, next);
      curves.add([
        start[0] + alpha * startSlope[0],
        start[1] + alpha * startSlope[1],
        end[0] - alpha * endSlope[0],
        end[1] - alpha * endSlope[1],
        end[0],
        end[1],
      ]);
      theta = next;
    }
    return curves;
  }

  static List<double> _ellipsePoint(double cx, double cy, double rx, double ry,
      double cosPhi, double sinPhi, double theta) {
    final cosTheta = math.cos(theta), sinTheta = math.sin(theta);
    return [
      cx + rx * cosPhi * cosTheta - ry * sinPhi * sinTheta,
      cy + rx * sinPhi * cosTheta + ry * cosPhi * sinTheta,
    ];
  }

  static List<double> _ellipseSlope(double rx, double ry, double cosPhi,
      double sinPhi, double theta) {
    final cosTheta = math.cos(theta), sinTheta = math.sin(theta);
    return [
      -rx * cosPhi * sinTheta - ry * sinPhi * cosTheta,
      -rx * sinPhi * sinTheta + ry * cosPhi * cosTheta,
    ];
  }
}
