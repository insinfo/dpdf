import 'dart:math';

import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/element/table.dart';
import 'package:dpdf/src/layout/element/cell.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/renderer/i_renderer.dart';
import 'package:dpdf/src/layout/renderer/cell_renderer.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/borders/border.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

class TableRenderer extends AbstractRenderer {
  List<double>? columns;
  List<List<CellRenderer?>> rows = [];

  TableRenderer(Table modelElement) : super(modelElement);

  @override
  Table getModelElement() {
    return super.getModelElement() as Table;
  }

  @override
  LayoutResult? layout(LayoutContext layoutContext) {
    LayoutArea area = layoutContext.getArea();
    Rectangle parentBox = area.getBBox().clone();
    double availableWidth = parentBox.getWidth();

    // Resolve columns
    prepareColumns(availableWidth);

    // Distribute cells into rows
    // This is a simplified grid builder.
    // Real iText handles overlapping and rowspanning more robustly.
    buildGrid();

    double curY = parentBox.getY() + parentBox.getHeight();
    double totalHeight = 0;

    // Layout rows
    // We need to determine row heights.
    // To do this, we layout each cell in the row with calculated width and infinite height.

    for (int r = 0; r < rows.length; r++) {
      List<CellRenderer?> row = rows[r];
      double rowHeight = 0;

      // Pass 1: Measure Max Height
      for (int c = 0; c < row.length; c++) {
        CellRenderer? cell = row[c];
        if (cell == null) continue; // Spanned placeholder or empty

        // Calculate cell width based on colspan
        double cellW = 0;
        // Find starting column index for this cell.
        // Since we just have a list, we might need to track indices better.
        // Simplified: assume rows[r][c] corresponds to grid column c?
        // Yes if we built grid correctly with nulls for spanned.

        int colspan = (cell.getModelElement() as Cell).colspan;
        double cellXOffset = 0;

        // Calc width and offset
        for (int k = 0; k < c; k++) cellXOffset += columns![k];
        for (int k = c; k < c + colspan && k < columns!.length; k++)
          cellW += columns![k];

        // Layout cell to find height
        // Provide infinite height to measure content
        LayoutArea cellMeasureArea =
            LayoutArea(1, Rectangle(0, 0, cellW, 10000));
        LayoutResult? measureResult =
            cell.layout(LayoutContext(cellMeasureArea));

        if (measureResult != null) {
          print(
              "Measure Cell [${r}][${c}]: Status=${measureResult.getStatus()}, Occupied=${measureResult.getOccupiedArea()}");
          if (measureResult.getOccupiedArea() != null) {
            double h = measureResult.getOccupiedArea()!.getBBox().getHeight();
            print("  Measured Height: $h");
            rowHeight = max(rowHeight, h);
          }
        } else {
          print("Measure Cell [${r}][${c}]: Result is NULL");
        }
      }

      // Pass 2: Set final rects
      double rowX = parentBox.getX();
      double currentColX = 0;

      for (int c = 0; c < columns!.length; c++) {
        if (c >= row.length) break;
        CellRenderer? cell = row[c];

        double colW = columns![c];

        if (cell != null) {
          int colspan = (cell.getModelElement() as Cell).colspan;
          double cellW = 0;
          for (int k = c; k < c + colspan && k < columns!.length; k++)
            cellW += columns![k];

          // Final layout with fixed height
          // Usually we stretch content or align.
          // BlockRenderer layout puts content at top.
          // We simply set occupiedArea for the cell so it knows where to draw borders/bg.

          // We re-layout? Or just set area?
          // If we re-layout with fixed height, it might split if content > height (but we set height = max content).
          // So re-layout is safe.

          LayoutArea finalArea = LayoutArea(
              area.getPageNumber(),
              Rectangle(
                  rowX + currentColX, curY - rowHeight, cellW, rowHeight));

          cell.layout(LayoutContext(finalArea));

          // Skip next columns if colspan
          // In our grid structure, next columns might be null or skipped in iteration logic if we iterate by renderer.
          // Here we iterate by column index.
          // If cell at [r][c] spans, [r][c+1] should be null/placeholder.
        }
        currentColX += colW;
      }

      curY -= rowHeight;
      totalHeight += rowHeight;

      // Check overflow (page break)
      if (totalHeight > parentBox.getHeight()) {
        // Primitive handling: just cut off or return partial?
        // For now, let's just finish.
        // TODO: partial result
      }
    }

    occupiedArea = LayoutArea(
        area.getPageNumber(),
        Rectangle(
            parentBox.getX(),
            parentBox.getY() + parentBox.getHeight() - totalHeight,
            availableWidth,
            totalHeight));

    return LayoutResult(LayoutResult.FULL, occupiedArea, null, null);
  }

  void prepareColumns(double availableWidth) {
    if (columns != null) return;
    Table table = getModelElement();
    List<UnitValue>? definedWidths = table.columnWidths;

    if (definedWidths == null || definedWidths.isEmpty) {
      // Default: single column?
      columns = [availableWidth];
      return;
    }

    columns = [];
    double totalDefined = 0;
    int nullCount = 0;

    for (var uv in definedWidths) {
      if (uv.isPointValue()) {
        columns!.add(uv.getValue());
        totalDefined += uv.getValue();
      } else if (uv.isPercentValue()) {
        double w = availableWidth * uv.getValue() / 100.0;
        columns!.add(w);
        totalDefined += w;
      } else {
        columns!.add(0); // placeholder for auto?
      }
    }

    // Normalize if total > available?
    // Or distribute remaining space?
    // Simple implementation: standard
  }

  void buildGrid() {
    // Flattens children into rows/cols
    if (rows.isNotEmpty) return;

    Table table = getModelElement();
    int colCount = columns?.length ?? 1;

    int r = 0;
    int c = 0;

    List<CellRenderer?> currentRow = List.filled(colCount, null);
    rows.add(currentRow);

    for (IRenderer child in childRenderers) {
      if (child is CellRenderer) {
        Cell cellModel = child.getModelElement() as Cell;
        int colspan = cellModel.colspan;

        // Find next available slot
        while (c < colCount && currentRow[c] != null) {
          c++;
        }
        if (c >= colCount) {
          // New row
          r++;
          c = 0;
          currentRow = List.filled(colCount, null);
          rows.add(currentRow);
        }

        if (c + colspan > colCount) {
          // Span exceeds row, force break or clip?
          colspan = colCount - c;
        }

        currentRow[c] = child;

        // Mark spanned slots
        for (int k = 1; k < colspan; k++) {
          // We need a way to mark "spanned". null is "empty".
          // But for this simple logic, if we iterate by column, we need to know NOT to render a new cell here.
          // But since childRenderers is a list of Cells, we only get "real" cells.
          // The grid 'currentRow' holds references.
          // If we put 'null' for spanned, we might confused it with empty.
          // Let's assume compact packing: no empty holes unless specified.
          // Actually, for simplicity, let's just advance 'c'.
        }
        c += colspan;
      }
    }
  }

  @override
  Future<void> draw(DrawContext drawContext) async {
    await super.draw(drawContext);
    // Borders are drawn by CellRenderers?
    // AbstractRenderer.drawBorder draws individual borders.
    // Table border?
  }

  @override
  MinMaxWidth? getMinMaxWidth() {
    return MinMaxWidth(0); // TODO implement
  }
}
