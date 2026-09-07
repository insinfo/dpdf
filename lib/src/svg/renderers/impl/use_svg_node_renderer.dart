import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Instancia uma cópia do elemento apontado por `href`/`xlink:href`.
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
      if (x != 0 || y != 0) canvas.concatMatrix(1, 0, 0, 1, x, y);
      final copy = template.createDeepCopy()..setParent(this);
      await copy.draw(context);
    } finally {
      context.removeUsedId(id);
      canvas.restoreState();
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
