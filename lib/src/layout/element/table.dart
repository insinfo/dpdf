import 'package:dpdf/src/layout/element/block_element.dart';
import 'package:dpdf/src/layout/element/cell.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/renderer/table_renderer.dart';
import 'package:dpdf/src/kernel/pdf/tagging/standard_roles.dart';
import 'package:dpdf/src/layout/tagging/default_accessibility_properties.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/properties/property.dart';

class Table extends BlockElement<Table> {
  List<UnitValue>? columnWidths;

  /// Header rows, repeated at the top of every area the table spans.
  final List<Cell> headerCells = [];

  /// Footer rows, repeated at the bottom of every area the table spans.
  final List<Cell> footerCells = [];

  DefaultAccessibilityProperties? _accessibilityProperties;

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

  /// Adds a cell to the repeating header (ISO 32000-1 tags it as `THead`).
  Table addHeaderCell(Cell cell) {
    cell.isHeader = true;
    headerCells.add(cell);
    return this;
  }

  /// Adds a cell to the repeating footer (`TFoot`).
  Table addFooterCell(Cell cell) {
    footerCells.add(cell);
    return this;
  }

  int get headerCellCount => headerCells.length;

  int get footerCellCount => footerCells.length;

  /// Suppresses the repetition of the header on subsequent areas.
  Table setSkipFirstHeader(bool skip) {
    setProperty(Property.IGNORE_HEADER, skip);
    return this;
  }

  /// Suppresses the repetition of the footer on subsequent areas.
  Table setSkipLastFooter(bool skip) {
    setProperty(Property.IGNORE_FOOTER, skip);
    return this;
  }

  // Override add to handle non-Cell additions? Usually strictly Cells in  7.
  // But BlockElement allows IElement.
  // We'll trust user adds Cells or wrappers.

  @override
  Renderer makeNewRenderer() {
    return TableRenderer(this);
  }

  @override
  DefaultAccessibilityProperties getAccessibilityProperties() {
    return _accessibilityProperties ??=
        DefaultAccessibilityProperties(StandardRoles.table);
  }
}
