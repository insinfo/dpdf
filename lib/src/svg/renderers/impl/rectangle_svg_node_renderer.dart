import 'dart:math' as math;

import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Renderizador de `<rect>`, com ou sem cantos arredondados.
class RectangleSvgNodeRenderer extends AbstractSvgNodeRenderer {
  /// Constante de aproximação de um quarto de circunferência por uma cúbica.
  static const double _kappa = 0.5522847498307933;

  double x = 0;
  double y = 0;
  double width = 0;
  double height = 0;
  double rx = 0;
  double ry = 0;

  void _setParameters(SvgDrawContext context) {
    x = parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.X, '0'), context);
    y = parseVerticalLength(
        getAttributeOrDefault(SvgAttributes.Y, '0'), context);
    width = parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.WIDTH, '0'), context);
    height = parseVerticalLength(
        getAttributeOrDefault(SvgAttributes.HEIGHT, '0'), context);

    final rxValue = getAttribute(SvgAttributes.RX);
    final ryValue = getAttribute(SvgAttributes.RY);
    rx = rxValue == null ? 0 : parseHorizontalLength(rxValue, context);
    ry = ryValue == null ? 0 : parseVerticalLength(ryValue, context);
    // Informar só um dos raios espelha o outro; declarar nenhum mantém os
    // cantos vivos.
    if (rxValue == null) rx = ry;
    if (ryValue == null) ry = rx;
    // A especificação limita cada raio a metade do lado correspondente.
    rx = math.min(math.max(rx, 0), width / 2);
    ry = math.min(math.max(ry, 0), height / 2);
  }

  @override
  Future<void> doDraw(SvgDrawContext context) async {
    _setParameters(context);
    if (width <= 0 || height <= 0) return;
    final canvas = context.getCurrentCanvas();
    if (rx <= 0 || ry <= 0) {
      canvas.rectangle(x, y, width, height);
      return;
    }
    _drawRoundedRectangle(canvas);
  }

  /// Os cantos são cúbicas explícitas em vez de `arc` porque assim o traçado
  /// fica descrito num único sistema de coordenadas, sem depender da convenção
  /// de ângulos do canvas — que é definida num espaço de Y crescente para
  /// cima, o oposto do espaço do SVG.
  void _drawRoundedRectangle(PdfCanvas canvas) {
    final right = x + width;
    final bottom = y + height;
    final dx = rx * _kappa;
    final dy = ry * _kappa;
    canvas
        .moveTo(x + rx, y)
        .lineTo(right - rx, y)
        .curveTo(right - rx + dx, y, right, y + ry - dy, right, y + ry)
        .lineTo(right, bottom - ry)
        .curveTo(right, bottom - ry + dy, right - rx + dx, bottom, right - rx,
            bottom)
        .lineTo(x + rx, bottom)
        .curveTo(x + rx - dx, bottom, x, bottom - ry + dy, x, bottom - ry)
        .lineTo(x, y + ry)
        .curveTo(x, y + ry - dy, x + rx - dx, y, x + rx, y)
        .closePath();
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) {
    _setParameters(context);
    return Rectangle(x, y, width, height);
  }

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = RectangleSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
