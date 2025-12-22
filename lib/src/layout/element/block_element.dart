import 'package:itext/src/layout/element/abstract_element.dart';
import 'package:itext/src/layout/element/i_element.dart';
import 'package:itext/src/layout/element/i_block_element.dart';
import 'package:itext/src/kernel/pdf/tagutils/accessibility_properties.dart';
import 'package:itext/src/layout/tagging/i_accessible_element.dart';

abstract class BlockElement<T extends IElement> extends AbstractElement<T>
    implements IBlockElement, IAccessibleElement {
  BlockElement();

  @override
  AccessibilityProperties getAccessibilityProperties();
}
