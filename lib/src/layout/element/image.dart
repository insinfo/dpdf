import 'package:pdfcraft/src/layout/element/abstract_element.dart';
import 'package:pdfcraft/src/layout/element/leaf_element.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';
import 'package:pdfcraft/src/layout/renderer/image_renderer.dart';
import 'package:pdfcraft/src/io/image/image_data.dart';
import 'package:pdfcraft/src/kernel/pdf/tagutils/accessibility_properties.dart';
import 'package:pdfcraft/src/layout/properties/property.dart';
import 'package:pdfcraft/src/layout/properties/unit_value.dart';

import 'package:pdfcraft/src/layout/tagging/accessible_element.dart';

class CraftImage extends CraftAbstractElement<CraftImage>
    implements CraftLeafContent, CraftAccessibleElement {
  final CraftImageData imageData;

  CraftImage(this.imageData);

  @override
  CraftRenderer makeNewRenderer() {
    return CraftImageRenderer(this);
  }

  @override
  CraftAccessibilityProperties getAccessibilityProperties() {
    return CraftAccessibilityProperties(); // TODO: Implement roles
  }

  CraftImage setWidth(double width) {
    setProperty(CraftProperty.WIDTH, CraftUnitValue.createPointValue(width));
    return this;
  }

  CraftImage setHeight(double height) {
    setProperty(CraftProperty.HEIGHT, CraftUnitValue.createPointValue(height));
    return this;
  }
}
