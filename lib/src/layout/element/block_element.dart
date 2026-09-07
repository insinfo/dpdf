import 'package:dpdf/src/layout/element/abstract_element.dart';
import 'package:dpdf/src/layout/element/element.dart';
import 'package:dpdf/src/layout/element/block_content.dart';
import 'package:dpdf/src/kernel/pdf/tagutils/accessibility_properties.dart';
import 'package:dpdf/src/layout/tagging/accessible_element.dart';

abstract class BlockElement<T extends Element> extends AbstractElement<T>
    implements BlockContent, AccessibleElement {
  BlockElement();

  @override
  AccessibilityProperties getAccessibilityProperties();
}
