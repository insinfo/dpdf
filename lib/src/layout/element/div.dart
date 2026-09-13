import 'package:dpdf/src/layout/element/block_element.dart';
import 'package:dpdf/src/layout/renderer/div_renderer.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/kernel/pdf/tagging/standard_roles.dart';
import 'package:dpdf/src/layout/tagging/default_accessibility_properties.dart';

class Div extends BlockElement<Div> {
  DefaultAccessibilityProperties? _accessibilityProperties;

  @override
  Renderer makeNewRenderer() {
    return DivRenderer(this);
  }

  @override
  DefaultAccessibilityProperties getAccessibilityProperties() {
    return _accessibilityProperties ??=
        DefaultAccessibilityProperties(StandardRoles.div);
  }
}
