import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';

/// Raiz sintética que assenta a árvore SVG sobre o canvas do PDF.
///
/// Existe por dois motivos que o elemento `<svg>` não pode resolver sozinho:
/// inverter o eixo Y (o SVG cresce para baixo, o PDF para cima) e informar
/// onde, na página, o desenho começa. Depois do `cm` de inversão, a origem
/// local passa a ser o canto superior esquerdo do [viewport] e todo o resto
/// da árvore trabalha em coordenadas locais — por isso o viewport empilhado
/// no contexto é ancorado em (0,0), e não na posição de página.
class PdfRootSvgNodeRenderer implements SvgNodeRenderer {
  final SvgNodeRenderer subTreeRoot;

  /// Área da página, em pontos, que o SVG vai ocupar.
  final Rectangle viewport;

  PdfRootSvgNodeRenderer(this.subTreeRoot, this.viewport) {
    subTreeRoot.setParent(this);
  }

  @override
  Future<void> draw(SvgDrawContext context) async {
    final canvas = context.getCurrentCanvas();
    canvas.saveState();
    canvas.concatMatrix(
        1, 0, 0, -1, viewport.getX(), viewport.getY() + viewport.getHeight());
    context.addViewPort(
        Rectangle(0, 0, viewport.getWidth(), viewport.getHeight()));
    try {
      await subTreeRoot.draw(context);
    } finally {
      context.removeCurrentViewPort();
      canvas.restoreState();
    }
  }

  @override
  SvgNodeRenderer? getParent() => null;

  /// A raiz não tem pai; a chamada é ignorada em vez de lançar, porque a
  /// interface é usada uniformemente por quem monta a árvore.
  @override
  void setParent(SvgNodeRenderer? parent) {}

  @override
  String? getAttribute(String key) => null;

  @override
  void setAttribute(String key, String value) {}

  @override
  void setAttributesAndStyles(Map<String, String> attributesAndStyles) {}

  @override
  Map<String, String> getAttributeMapCopy() => <String, String>{};

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() =>
      PdfRootSvgNodeRenderer(subTreeRoot.createDeepCopy(), viewport);
}
