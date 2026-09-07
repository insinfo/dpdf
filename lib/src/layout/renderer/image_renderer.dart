import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/element/image.dart';
import 'package:dpdf/src/kernel/pdf/xobject/pdf_image_x_object.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';

class CraftImageRenderer extends CraftAbstractRenderer {
  late double _imageWidth;
  late double _imageHeight;

  CraftImageRenderer(CraftImage modelElement) : super(modelElement) {
    _imageWidth = modelElement.imageData.width;
    _imageHeight = modelElement.imageData.height;
  }

  @override
  CraftLayoutResult layout(CraftLayoutContext layoutContext) {
    final area = layoutContext.getArea();
    final layoutBox = area.getBBox().clone();

    double width =
        getProperty<CraftUnitValue>(CraftProperty.WIDTH)?.getValue() ??
            _imageWidth;
    double height =
        getProperty<CraftUnitValue>(CraftProperty.HEIGHT)?.getValue() ??
            _imageHeight;

    if (width > layoutBox.getWidth()) {
      // Simple fitting for now
      return CraftLayoutResult(
          CraftLayoutResult.NOTHING, null, null, this, this);
    }

    // Simplified layout: just occupation of width/height
    occupiedArea = CraftLayoutArea(
        area.pageOrdinal(),
        CraftRectangle(layoutBox.getX(),
            layoutBox.getY() + layoutBox.getHeight() - height, width, height));

    return CraftLayoutResult(CraftLayoutResult.FULL, occupiedArea, null, null);
  }

  @override
  Future<void> draw(CraftDrawContext drawContext) async {
    if (occupiedArea == null) return;

    final image = getModelElement() as CraftImage;
    final xObject = CraftPdfImageXObject(image.imageData);

    final box = occupiedArea!.getBBox();
    await drawContext.getCanvas().addXObjectWithTransformationMatrix(
        xObject.pdfRepresentation(),
        box.getWidth(),
        0,
        0,
        box.getHeight(),
        box.getX(),
        box.getY());
  }

  @override
  CraftRenderer getNextRenderer() {
    return CraftImageRenderer(getModelElement() as CraftImage);
  }
}
