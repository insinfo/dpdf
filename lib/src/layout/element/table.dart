import 'package:pdfcraft/src/layout/element/block_element.dart';
import 'package:pdfcraft/src/layout/element/cell.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';
import 'package:pdfcraft/src/layout/renderer/table_renderer.dart';
import 'package:pdfcraft/src/kernel/pdf/tagutils/accessibility_properties.dart';
import 'package:pdfcraft/src/layout/properties/unit_value.dart';

class CraftTable extends CraftBlockElement<CraftTable> {
  List<CraftUnitValue>? columnWidths;

  // Basic constructor with point widths (float array)
  CraftTable.fromPointColumnWidths(List<double> columnWidths) {
    this.columnWidths = [];
    for (double w in columnWidths) {
      if (w >= 0) {
        this.columnWidths!.add(CraftUnitValue.createPointValue(w));
      } else {
        // Handle auto/percent? For now assume valid point values or simple default
        this.columnWidths!.add(CraftUnitValue.createPointValue(0));
      }
    }
    _init();
  }

  // Standard constructor with UnitValue array
  CraftTable(List<CraftUnitValue> columnWidths) {
    this.columnWidths = columnWidths;
    _init();
  }

  void _init() {
    // Default properties if needed
  }

  CraftTable addCell(CraftCell cell) {
    childElements.add(cell);
    return this;
  }

  // Override add to handle non-Cell additions? Usually strictly Cells in  7.
  // But BlockElement allows IElement.
  // We'll trust user adds Cells or wrappers.

  @override
  CraftRenderer makeNewRenderer() {
    return CraftTableRenderer(this);
  }

  @override
  CraftAccessibilityProperties getAccessibilityProperties() {
    return CraftAccessibilityProperties();
  }
}
