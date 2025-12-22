import 'package:dpdf/src/layout/element/block_element.dart';
import 'package:dpdf/src/layout/element/cell.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/renderer/table_renderer.dart';
import 'package:dpdf/src/kernel/pdf/tagutils/accessibility_properties.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';

class Table extends BlockElement<Table> {
  List<UnitValue>? columnWidths;

  // Basic constructor with point widths (float array)
  Table.fromPointColumnWidths(List<double> columnWidths) {
    this.columnWidths = [];
    for (double w in columnWidths) {
      if (w >= 0) {
        this.columnWidths!.add(UnitValue.createPointValue(w));
      } else {
        // Handle auto/percent? For now assume valid point values or simple default
        this.columnWidths!.add(UnitValue.createPointValue(0));
      }
    }
    _init();
  }

  // Standard constructor with UnitValue array
  Table(List<UnitValue> columnWidths) {
    this.columnWidths = columnWidths;
    _init();
  }

  void _init() {
    // Default properties if needed
  }

  Table addCell(Cell cell) {
    childElements.add(cell);
    return this;
  }

  // Override add to handle non-Cell additions? Usually strictly Cells in iText 7.
  // But BlockElement allows IElement.
  // We'll trust user adds Cells or wrappers.

  @override
  IRenderer makeNewRenderer() {
    return TableRenderer(this);
  }

  @override
  AccessibilityProperties getAccessibilityProperties() {
    return AccessibilityProperties();
  }
}
