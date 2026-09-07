import 'package:dpdf/src/layout/element/block_element.dart';
import 'package:dpdf/src/layout/element/element.dart';
import 'package:dpdf/src/layout/renderer/cell_renderer.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
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

  @override
  Cell add(Element element) {
    childElements.add(element);
    return this;
  }

  @override
  Renderer makeNewRenderer() {
    return CellRenderer(this);
  }

  @override
  AccessibilityProperties getAccessibilityProperties() {
    return AccessibilityProperties();
  }
}
