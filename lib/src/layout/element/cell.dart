import 'package:dpdf/src/layout/element/block_element.dart';
import 'package:dpdf/src/layout/element/element.dart';
import 'package:dpdf/src/layout/renderer/cell_renderer.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/kernel/pdf/tagging/standard_roles.dart';
import 'package:dpdf/src/layout/tagging/default_accessibility_properties.dart';
import 'package:dpdf/src/layout/properties/property.dart';

class Cell extends BlockElement<Cell> {
  int rowspan = 1;
  int colspan = 1;

  /// Header cells are tagged as `TH` instead of `TD` (ISO 32000-1, 14.8.4.3.4).
  bool isHeader = false;

  DefaultAccessibilityProperties? _accessibilityProperties;

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
  DefaultAccessibilityProperties getAccessibilityProperties() {
    return _accessibilityProperties ??= DefaultAccessibilityProperties(
        isHeader ? StandardRoles.th : StandardRoles.td);
  }
}
