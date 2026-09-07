import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

class ClipPathSvgNodeRenderer extends AbstractBranchSvgNodeRenderer {
  SvgNodeRenderer? _clippedRenderer;

  @override
  Future<void> draw(SvgDrawContext context) async {
    final target = _clippedRenderer;
    if (target == null || isHidden()) return;
    final canvas = context.getCurrentCanvas();
    canvas.saveState();
    try {
      await super.doDraw(context);
      final rule = getAttribute(SvgAttributes.CLIP_RULE) ?? '';
      if (rule.toLowerCase() == SvgValues.FILL_RULE_EVEN_ODD) {
        canvas.eoClip();
      } else {
        canvas.clip();
      }
      canvas.newPath();

      final copy = target.createDeepCopy();
      final attributes = copy.getAttributeMapCopy()
        ..remove(SvgAttributes.CLIP_PATH);
      copy
        ..setAttributesAndStyles(attributes)
        ..setParent(target.getParent());
      await copy.draw(context);
    } finally {
      canvas.restoreState();
    }
  }

  void setClippedRenderer(SvgNodeRenderer renderer) {
    _clippedRenderer = renderer;
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = ClipPathSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}
