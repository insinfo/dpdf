import 'package:dpdf/src/layout/element/block_element.dart';
import 'package:dpdf/src/layout/renderer/div_renderer.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/kernel/pdf/tagutils/accessibility_properties.dart';

class CraftDiv extends CraftBlockElement<CraftDiv> {
  @override
  CraftRenderer makeNewRenderer() {
    return CraftDivRenderer(this);
  }

  @override
  CraftAccessibilityProperties getAccessibilityProperties() {
    return CraftAccessibilityProperties();
  }
}
