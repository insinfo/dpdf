import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/marker_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/no_draw_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/utils/svg_conditional_processing.dart';

/// Renderizador de `<switch>` (SVG 1.1 §5.8.2).
///
/// Desenha o primeiro filho direto desenhável cujos `requiredFeatures`,
/// `requiredExtensions` e `systemLanguage` avaliam verdadeiro, e ignora todos
/// os demais — inclusive os que também passariam no teste.
class SwitchSvgNodeRenderer extends AbstractBranchSvgNodeRenderer {
  @override
  bool canElementFill() => false;

  @override
  Future<void> doDraw(SvgDrawContext context) async {
    final chosen = _selectChild();
    if (chosen == null) return;
    final canvas = context.getCurrentCanvas();
    canvas.saveState();
    try {
      await chosen.draw(context);
    } finally {
      canvas.restoreState();
    }
  }

  /// Elementos sem representação visual (`<defs>`, `<title>`, `<desc>`,
  /// `<style>`) e marcadores não são candidatos: a especificação restringe a
  /// escolha aos elementos desenháveis diretos.
  SvgNodeRenderer? _selectChild() {
    for (final child in getChildren()) {
      if (child is NoDrawSvgNodeRenderer) continue;
      if (child is MarkerSvgNodeRenderer) continue;
      if (SvgConditionalProcessing.isRendered(child)) return child;
    }
    return null;
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = SwitchSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}
