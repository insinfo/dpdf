import 'package:pdfcraft/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:pdfcraft/src/svg/renderers/svg_draw_context.dart';
import 'package:pdfcraft/src/kernel/geom/rectangle.dart';

abstract class CraftAbstractContainerSvgNodeRenderer
    extends CraftAbstractBranchSvgNodeRenderer {
  @override
  bool canConstructViewPort() => true;

  @override
  bool canElementFill() => false;

  @override
  Future<void> doDraw(CraftSvgDrawContext context) async {
    context.addViewPort(calculateViewPort(context));
    await super.doDraw(context);
  }

  CraftRectangle calculateViewPort(CraftSvgDrawContext context) {
    // Basic implementation for now, can be expanded to match C# logic
    // TODO: Fully implement nested viewport calculation
    return context.getCurrentViewPort() ?? CraftRectangle(0, 0, 0, 0);
  }
}
