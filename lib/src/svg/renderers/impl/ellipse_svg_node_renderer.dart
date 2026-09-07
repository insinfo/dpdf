import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Renderizador de `<ellipse>`, e base de `<circle>`.
class EllipseSvgNodeRenderer extends AbstractSvgNodeRenderer {
  double cx = 0;
  double cy = 0;
  double rx = 0;
  double ry = 0;

  /// Resolve centro e raios. Devolve `false` quando a elipse é degenerada —
  /// raio ausente ou não positivo desliga o desenho, em vez de emitir um
  /// caminho vazio que ainda assim consumiria o operador de pintura.
  bool setParameters(SvgDrawContext context) {
    initCenter(context);
    final rxValue = getAttribute(SvgAttributes.RX);
    final ryValue = getAttribute(SvgAttributes.RY);
    rx = rxValue == null ? 0 : parseHorizontalLength(rxValue, context);
    ry = ryValue == null ? 0 : parseVerticalLength(ryValue, context);
    // `auto` de um dos eixos herda o outro, conforme SVG 2.
    if (rxValue == null) rx = ry;
    if (ryValue == null) ry = rx;
    return rx > 0 && ry > 0;
  }

  void initCenter(SvgDrawContext context) {
    cx = parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.CX, '0'), context);
    cy = parseVerticalLength(
        getAttributeOrDefault(SvgAttributes.CY, '0'), context);
  }

  @override
  Future<void> doDraw(SvgDrawContext context) async {
    if (!setParameters(context)) return;
    final canvas = context.getCurrentCanvas();
    // O `arc` do canvas só emite curvas; o ponto inicial tem de ser posto à
    // mão, senão a elipse continuaria o subcaminho anterior.
    canvas.moveTo(cx + rx, cy);
    canvas.arc(cx - rx, cy - ry, cx + rx, cy + ry, 0, 360);
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) {
    if (!setParameters(context)) return null;
    return Rectangle(cx - rx, cy - ry, rx * 2, ry * 2);
  }

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = EllipseSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
