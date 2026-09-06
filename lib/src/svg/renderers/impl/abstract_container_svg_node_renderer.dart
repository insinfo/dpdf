import 'package:dpdf/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';

abstract class AbstractContainerSvgNodeRenderer
    extends AbstractBranchSvgNodeRenderer {
  @override
  bool canConstructViewPort() => true;

  @override
  bool canElementFill() => false;

  @override
  Future<void> doDraw(SvgDrawContext context) async {
    context.addViewPort(calculateViewPort(context));
    await super.doDraw(context);
  }

  Rectangle calculateViewPort(SvgDrawContext context) {
    // Basic implementation for now, can be expanded to match C# logic
    // TODO: Fully implement nested viewport calculation
    return context.getCurrentViewPort() ?? Rectangle(0, 0, 0, 0);
  }
}
