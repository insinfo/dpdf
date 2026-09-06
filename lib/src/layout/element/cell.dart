import 'package:dpdf/src/layout/element/block_element.dart';
import 'package:dpdf/src/layout/element/i_element.dart';
import 'package:dpdf/src/layout/renderer/cell_renderer.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/kernel/pdf/tagutils/accessibility_properties.dart';
import 'package:dpdf/src/layout/properties/property.dart';

class Cell extends BlockElement<Cell> {
  int rowspan = 1;
  int colspan = 1;

  Cell([int rowspan = 1, int colspan = 1]) {
    this.rowspan = rowspan;
    this.colspan = colspan;
    setProperty(Property.ROWSPAN, rowspan);
    setProperty(Property.COLSPAN, colspan);
  }

  Cell add(IElement element) {
    childElements.add(element);
    return this;
  }

  @override
  IRenderer makeNewRenderer() {
    return CellRenderer(this);
  }

  @override
  AccessibilityProperties getAccessibilityProperties() {
    return AccessibilityProperties();
  }
}
