import 'package:dpdf/src/layout/element/abstract_element.dart';
import 'package:dpdf/src/layout/element/leaf_content.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/renderer/image_renderer.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/kernel/pdf/tagutils/accessibility_properties.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';

import 'package:dpdf/src/layout/tagging/accessible_element.dart';

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

  @override
  CraftImage setWidth(double width) {
    setProperty(CraftProperty.WIDTH, CraftUnitValue.createPointValue(width));
    return this;
  }

  @override
  CraftImage setHeight(double height) {
    setProperty(CraftProperty.HEIGHT, CraftUnitValue.createPointValue(height));
    return this;
  }
}
