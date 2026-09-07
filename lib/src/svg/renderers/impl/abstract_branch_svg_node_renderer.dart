import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/xobject/pdf_form_x_object.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/marker_svg_node_renderer.dart';

abstract class CraftAbstractBranchSvgNodeRenderer
    extends CraftAbstractSvgNodeRenderer implements CraftBranchSvgNodeRenderer {
  final List<CraftSvgNodeRenderer> _children = [];

  @override
  Future<void> doDraw(CraftSvgDrawContext context) async {
    if (_children.isNotEmpty) {
      CraftRectangle currentViewPort = context.getCurrentViewPort()!;
      CraftPdfFormXObject xObject = CraftPdfFormXObject(currentViewPort);
      CraftPdfCanvas newCanvas = await CraftPdfCanvas.fromFormXObject(
          xObject, context.getCurrentCanvas().getDocument()!);

      // TODO: Apply ViewBox

      context.pushCanvas(newCanvas);

      for (var child in _children) {
        if (child is! CraftMarkerSvgNodeRenderer) {
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
  void addChild(CraftSvgNodeRenderer child) {
    _children.add(child);
  }

  @override
  List<CraftSvgNodeRenderer> getChildren() {
    return List.unmodifiable(_children);
  }

  void deepCopyChildren(CraftAbstractBranchSvgNodeRenderer deepCopy) {
    for (var child in _children) {
      CraftSvgNodeRenderer newChild = child.createDeepCopy();
      newChild.setParent(deepCopy);
      deepCopy.addChild(newChild);
    }
  }

  @override
  CraftSvgNodeRenderer createDeepCopy();
}
