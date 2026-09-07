import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/no_draw_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';

/// Renderizador de elementos que existem na árvore mas nunca pintam nada
/// diretamente: `<defs>`, `<title>`, `<desc>`, `<metadata>`, `<style>`.
///
/// Mantê-los como nós (em vez de descartá-los na montagem) preserva o
/// caminho para resolvê-los por referência mais tarde, sem que o conteúdo
/// vaze para o fluxo de desenho.
class CraftNoOpSvgNodeRenderer extends CraftAbstractBranchSvgNodeRenderer
    implements CraftNoDrawSvgNodeRenderer {
  @override
  bool canElementFill() => false;

  @override
  Future<void> doDraw(CraftSvgDrawContext context) async {}

  @override
  Future<void> preDraw(CraftSvgDrawContext context) async {}

  @override
  Future<void> postDraw(CraftSvgDrawContext context) async {}

  @override
  CraftRectangle? getObjectBoundingBox(CraftSvgDrawContext context) => null;

  @override
  CraftSvgNodeRenderer createDeepCopy() {
    final copy = CraftNoOpSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}
