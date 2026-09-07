import 'package:dpdf/src/layout/element/abstract_element.dart';
import 'package:dpdf/src/layout/element/leaf_content.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/renderer/image_renderer.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/kernel/pdf/tagutils/accessibility_properties.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';

import 'package:dpdf/src/layout/tagging/accessible_element.dart';

class Image extends AbstractElement<Image>
    implements LeafContent, AccessibleElement {
  final ImageData imageData;

  Image(this.imageData);

  @override
  Renderer makeNewRenderer() {
    return ImageRenderer(this);
  }

  @override
  AccessibilityProperties getAccessibilityProperties() {
    return AccessibilityProperties(); // TODO: Implement roles
  }

  @override
  Image setWidth(double width) {
    setProperty(Property.WIDTH, UnitValue.createPointValue(width));
    return this;
  }

  @override
  Image setHeight(double height) {
    setProperty(Property.HEIGHT, UnitValue.createPointValue(height));
    return this;
  }
}
