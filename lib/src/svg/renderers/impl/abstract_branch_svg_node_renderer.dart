import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/xobject/pdf_form_x_object.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/i_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/i_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/marker_svg_node_renderer.dart';

abstract class AbstractBranchSvgNodeRenderer extends AbstractSvgNodeRenderer
    implements IBranchSvgNodeRenderer {
  final List<ISvgNodeRenderer> _children = [];

  @override
  Future<void> doDraw(SvgDrawContext context) async {
    if (_children.isNotEmpty) {
      Rectangle currentViewPort = context.getCurrentViewPort()!;
      PdfFormXObject xObject = PdfFormXObject(currentViewPort);
      PdfCanvas newCanvas = await PdfCanvas.fromFormXObject(
          xObject, context.getCurrentCanvas().getDocument()!);

      // TODO: Apply ViewBox

      context.pushCanvas(newCanvas);

      for (var child in _children) {
        if (child is! MarkerSvgNodeRenderer) {
          await child.draw(context);
        }
      }

      context.popCanvas();

      await context
          .getCurrentCanvas()
          .addXObject(xObject, currentViewPort.getX(), currentViewPort.getY());
    }
  }

  @override
  void addChild(ISvgNodeRenderer child) {
    _children.add(child);
  }

  @override
  List<ISvgNodeRenderer> getChildren() {
    return List.unmodifiable(_children);
  }

  void deepCopyChildren(AbstractBranchSvgNodeRenderer deepCopy) {
    for (var child in _children) {
      ISvgNodeRenderer newChild = child.createDeepCopy();
      newChild.setParent(deepCopy);
      deepCopy.addChild(newChild);
    }
  }

  @override
  ISvgNodeRenderer createDeepCopy();
}
