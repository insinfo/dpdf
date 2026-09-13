import 'package:dpdf/src/layout/element/abstract_element.dart';
import 'package:dpdf/src/layout/element/leaf_content.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/renderer/image_renderer.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/kernel/pdf/tagging/standard_roles.dart';
import 'package:dpdf/src/layout/tagging/default_accessibility_properties.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';

import 'package:dpdf/src/layout/tagging/accessible_element.dart';

class Image extends AbstractElement<Image>
    implements LeafContent, AccessibleElement {
  final ImageData imageData;
  DefaultAccessibilityProperties? _accessibilityProperties;

  Image(this.imageData);

  @override
  Renderer makeNewRenderer() {
    return ImageRenderer(this);
  }

  /// Images map to the `Figure` standard structure type (ISO 32000-1, 14.8.4).
  @override
  DefaultAccessibilityProperties getAccessibilityProperties() {
    return _accessibilityProperties ??=
        DefaultAccessibilityProperties(StandardRoles.figure);
  }

  /// Alternate description used as `/Alt` of the `Figure` structure element.
  Image setAlternateDescription(String? description) {
    getAccessibilityProperties().setAlternateDescription(description);
    return this;
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
