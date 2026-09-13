import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/css/impl/svg_node_renderer_inheritance_resolver.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/svg_tag_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/symbol_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Instancia uma cópia do elemento apontado por `href`/`xlink:href`
/// (SVG 1.1 §5.6).
class UseSvgNodeRenderer extends AbstractSvgNodeRenderer {
  @override
  bool canElementFill() => false;

  @override
  Future<void> preDraw(SvgDrawContext context) async {}

  @override
  Future<void> postDraw(SvgDrawContext context) async {}

  @override
  Future<void> doDraw(SvgDrawContext context) async {
    final href = getAttribute(SvgAttributes.HREF) ??
        getAttribute(SvgAttributes.XLINK_HREF);
    if (href == null || !href.trim().startsWith('#')) return;
    final id = href.trim().substring(1);
    final template = context.getNamedObject(id);
    if (template == null || context.isIdUsedByUseTagBefore(id)) return;

    final x = parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.X, '0'), context);
    final y = parseVerticalLength(
        getAttributeOrDefault(SvgAttributes.Y, '0'), context);
    final canvas = context.getCurrentCanvas();
    canvas.saveState();
    context.addUsedId(id);
    try {
      // `x` e `y` viram uma translação — §5.6 descreve a instância como
      // envolvida por um `<g transform="translate(x,y)">`.
      if (x != 0 || y != 0) canvas.concatMatrix(1, 0, 0, 1, x, y);
      final copy = template.createDeepCopy()..setParent(this);
      _prepareInstance(copy);
      // A cópia é desenhada como se fosse filha do `<use>`, então herda dele
      // as propriedades que ainda não declarou.
      SvgNodeRendererInheritanceResolver.applyInheritanceToSubTree(
          this, copy, context.getCssContext());
      await copy.draw(context);
    } finally {
      context.removeUsedId(id);
      canvas.restoreState();
    }
  }

  /// Ajusta a instância ao que a especificação manda gerar.
  ///
  /// `<symbol>` vira um `<svg>` cujo viewport recebe a largura e a altura
  /// declaradas no `<use>`, e `100%` quando elas faltam; um `<svg>`
  /// referenciado só tem essas duas medidas substituídas, mantendo as
  /// próprias `x` e `y`.
  void _prepareInstance(SvgNodeRenderer copy) {
    final width = getAttribute(SvgAttributes.WIDTH);
    final height = getAttribute(SvgAttributes.HEIGHT);
    if (copy is SymbolSvgNodeRenderer) {
      copy.markInstantiated();
      // A posição já foi resolvida pela translação; deixar `x`/`y` no
      // símbolo deslocaria a instância uma segunda vez.
      copy
        ..setAttribute(SvgAttributes.X, '0')
        ..setAttribute(SvgAttributes.Y, '0')
        ..setAttribute(SvgAttributes.WIDTH,
            width ?? SvgValues.DEFAULT_WIDTH_AND_HEIGHT_VALUE)
        ..setAttribute(SvgAttributes.HEIGHT,
            height ?? SvgValues.DEFAULT_WIDTH_AND_HEIGHT_VALUE);
      return;
    }
    if (copy is SvgTagSvgNodeRenderer) {
      if (width != null) copy.setAttribute(SvgAttributes.WIDTH, width);
      if (height != null) copy.setAttribute(SvgAttributes.HEIGHT, height);
    }
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = UseSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
