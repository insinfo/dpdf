import 'package:dpdf/src/kernel/pdf/tagutils/accessibility_properties.dart';

/// Accessibility properties of a layout element, pre-filled with the standard
/// structure type the element maps to (ISO 32000-1, 14.8.4 "Standard Structure
/// Types"). Everything else - `/Lang`, `/Alt`, `/E`, `/ActualText`, attribute
/// objects - is inherited from the kernel tagging API and applied to the
/// structure element by [AccessibilityProperties.applyTo].
class DefaultAccessibilityProperties extends AccessibilityProperties {
  DefaultAccessibilityProperties([String? role]) {
    if (role != null) {
      setRole(role);
    }
  }

  @override
  String toString() => 'AccessibilityProperties{role: ${getRole()}}';
}
