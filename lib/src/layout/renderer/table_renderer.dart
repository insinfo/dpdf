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

      // Pass 1: Measure Max Height for rowspan=1 cells
      for (int c = 0; c < row.length; c++) {
        CellRenderer? cell = row[c];
        if (cell == null || isPlaceholder(r, c)) continue;

        Cell cellModel = cell.getModelElement() as Cell;
        if (cellModel.rowspan > 1)
          continue; // TODO: handle rowspan height distribution

        double cellW = getCellWidth(c, cellModel.colspan);

        LayoutArea cellMeasureArea =
            LayoutArea(area.getPageNumber(), Rectangle(0, 0, cellW, 10000));
        LayoutResult? measureResult =
            cell.layout(LayoutContext(cellMeasureArea));

        if (measureResult != null && measureResult.getOccupiedArea() != null) {
          double h = measureResult.getOccupiedArea()!.getBBox().getHeight();
          rowHeight = max(rowHeight, h);
        }
      }

      // Check for available height
      if (totalHeight + rowHeight > parentBox.getHeight() && r > 0) {
        TableRenderer splitRenderer =
            createSplitRenderer(LayoutResult.PARTIAL) as TableRenderer;
        splitRenderer.rows = rows.sublist(0, r);

        TableRenderer overflowRenderer =
            createOverflowRenderer(LayoutResult.PARTIAL) as TableRenderer;
        overflowRenderer.rows = rows.sublist(r);

        occupiedArea = LayoutArea(
            area.getPageNumber(),
            Rectangle(
                parentBox.getX(),
                parentBox.getY() + parentBox.getHeight() - totalHeight,
                parentBox.getWidth(),
                totalHeight));
        return LayoutResult(LayoutResult.PARTIAL, occupiedArea, splitRenderer,
            overflowRenderer);
      }

      // Pass 2: Set final rects for this row
      double currentColX = 0;
      for (int c = 0; c < columns!.length; c++) {
        if (c >= row.length) break;
        CellRenderer? cell = row[c];
        double colW = columns![c];

        if (cell != null && !isPlaceholder(r, c)) {
          Cell cellModel = cell.getModelElement() as Cell;
          double cellW = getCellWidth(c, cellModel.colspan);
          double cellH = rowHeight;

          LayoutArea finalArea = LayoutArea(
              area.getPageNumber(),
              Rectangle(
                  parentBox.getX() + currentColX, curY - cellH, cellW, cellH));
          cell.layout(LayoutContext(finalArea));
        }
        currentColX += colW;
      }

      curY -= rowHeight;
      totalHeight += rowHeight;
    }

    double tableWidth = 0;
    if (columns != null) {
      for (var w in columns!) tableWidth += w;
    } else {
      tableWidth = availableWidth;
    }

    occupiedArea = LayoutArea(
        area.getPageNumber(),
        Rectangle(
            parentBox.getX(),
            parentBox.getY() + parentBox.getHeight() - totalHeight,
            tableWidth,
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
    // double totalDefined = 0;
    // int nullCount = 0;

    for (var uv in definedWidths) {
      if (uv.isPointValue()) {
        columns!.add(uv.getValue());
        // totalDefined += uv.getValue();
      } else if (uv.isPercentValue()) {
        double w = availableWidth * uv.getValue() / 100.0;
        columns!.add(w);
        // totalDefined += w;
      } else {
        columns!.add(0); // placeholder for auto?
      }
    }

    // Normalize if total > available?
    // Or distribute remaining space?
    // Simple implementation: standard
  }

  void buildGrid() {
    if (rows.isNotEmpty) return;

    int colCount = columns?.length ?? 1;
    int r = 0;
    int c = 0;

    for (IRenderer child in childRenderers) {
      if (child is CellRenderer) {
        Cell cellModel = child.getModelElement() as Cell;
        int colspan = cellModel.colspan;
        int rowspan = cellModel.rowspan;

        // Find next available slot
        while (true) {
          if (r >= rows.length) {
            rows.add(List.filled(colCount, null));
          }
          if (c >= colCount) {
            r++;
            c = 0;
            continue;
          }
          if (rows[r][c] != null) {
            c++;
            continue;
          }
          break;
        }

        // Clip spans to grid
        if (c + colspan > colCount) colspan = colCount - c;

        // Fill slots
        for (int i = 0; i < rowspan; i++) {
          for (int j = 0; j < colspan; j++) {
            int rowIdx = r + i;
            int colIdx = c + j;
            while (rowIdx >= rows.length) {
              rows.add(List.filled(colCount, null));
            }
            // Use a placeholder if it's not the origin of span
            if (i == 0 && j == 0) {
              rows[rowIdx][colIdx] = child;
            } else {
              // We need a specific placeholder object to distinguish from empty (null)
              rows[rowIdx][colIdx] = _CellPlaceholder(child);
            }
          }
        }
        c += colspan;
      }
    }
  }

  bool isPlaceholder(int r, int c) {
    return rows[r][c] is _CellPlaceholder;
  }

  double getCellWidth(int startCol, int colspan) {
    double w = 0;
    for (int i = startCol; i < startCol + colspan && i < columns!.length; i++) {
      w += columns![i];
    }
    return w;
  }

  @override
  Future<void> draw(DrawContext drawContext) async {
    await super.draw(drawContext);
    // Borders are drawn by CellRenderers?
    // AbstractRenderer.drawBorder draws individual borders.
    // Table border?
  }

  @override
  IRenderer getNextRenderer() {
    return TableRenderer(getModelElement());
  }

  @override
  AbstractRenderer createSplitRenderer(int layoutResult) {
    TableRenderer splitRenderer = getNextRenderer() as TableRenderer;
    splitRenderer.modelElement = modelElement;
    splitRenderer.parent = parent;
    splitRenderer.columns = columns;
    return splitRenderer;
  }

  @override
  AbstractRenderer createOverflowRenderer(int layoutResult) {
    TableRenderer overflowRenderer = getNextRenderer() as TableRenderer;
    overflowRenderer.modelElement = modelElement;
    overflowRenderer.parent = parent;
    overflowRenderer.columns = columns;
    return overflowRenderer;
  }
}

class _CellPlaceholder extends CellRenderer {
  final CellRenderer origin;
  _CellPlaceholder(this.origin) : super(origin.getModelElement() as Cell);
}
