import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/element/image.dart';
import 'package:dpdf/src/kernel/pdf/xobject/pdf_image_x_object.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';

class ImageRenderer extends AbstractRenderer {
  late double _imageWidth;
  late double _imageHeight;

  ImageRenderer(Image modelElement) : super(modelElement) {
    _imageWidth = modelElement.imageData.width;
    _imageHeight = modelElement.imageData.height;
  }

  @override
  LayoutResult layout(LayoutContext layoutContext) {
    final area = layoutContext.getArea();
    final layoutBox = area.getBBox().clone();

    double width =
        getProperty<UnitValue>(Property.WIDTH)?.getValue() ?? _imageWidth;
    double height =
        getProperty<UnitValue>(Property.HEIGHT)?.getValue() ?? _imageHeight;

    print(
        "ImageRenderer.layout: width=$width, layoutBoxWidth=${layoutBox.getWidth()}");
    if (width > layoutBox.getWidth()) {
      // Simple fitting for now
      print("ImageRenderer.layout: width > layoutBoxWidth, returning NOTHING");
      return LayoutResult(LayoutResult.NOTHING, null, null, this, this);
    }

    // Simplified layout: just occupation of width/height
    occupiedArea = LayoutArea(
        area.getPageNumber(),
        Rectangle(layoutBox.getX(),
            layoutBox.getY() + layoutBox.getHeight() - height, width, height));

    return LayoutResult(LayoutResult.FULL, occupiedArea, null, null);
  }

  @override
  Future<void> draw(DrawContext drawContext) async {
    if (occupiedArea == null) return;

    final image = getModelElement() as Image;
    final xObject = PdfImageXObject(image.imageData);

    final box = occupiedArea!.getBBox();
    await drawContext.getCanvas().addXObjectWithTransformationMatrix(
        xObject.getPdfObject(),
        box.getWidth(),
        0,
        0,
        box.getHeight(),
        box.getX(),
        box.getY());
  }

  @override
  IRenderer getNextRenderer() {
    return ImageRenderer(getModelElement() as Image);
  }
}
