import 'package:dpdf/src/layout/element/block_element.dart';
import 'package:dpdf/src/layout/renderer/div_renderer.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/kernel/pdf/tagutils/accessibility_properties.dart';

class Div extends BlockElement<Div> {
  @override
  Renderer makeNewRenderer() {
    return DivRenderer(this);
  }

  @override
  AccessibilityProperties getAccessibilityProperties() {
    return AccessibilityProperties();
  }
}
