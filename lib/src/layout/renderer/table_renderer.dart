import 'dart:math';

import 'package:pdfcraft/src/layout/renderer/abstract_renderer.dart';
import 'package:pdfcraft/src/layout/element/table.dart';
import 'package:pdfcraft/src/layout/element/cell.dart';
import 'package:pdfcraft/src/layout/layout/layout_context.dart';
import 'package:pdfcraft/src/layout/layout/layout_result.dart';
import 'package:pdfcraft/src/layout/renderer/draw_context.dart';
import 'package:pdfcraft/src/layout/layout/layout_area.dart';
import 'package:pdfcraft/src/kernel/geom/rectangle.dart';
import 'package:pdfcraft/src/layout/properties/unit_value.dart';
import 'package:pdfcraft/src/layout/renderer/renderer.dart';
import 'package:pdfcraft/src/layout/renderer/cell_renderer.dart';

class CraftTableRenderer extends CraftAbstractRenderer {
  List<double>? columns;
  List<List<CraftCellRenderer?>> rows = [];

  CraftTableRenderer(CraftTable modelElement) : super(modelElement);

  @override
  CraftTable getModelElement() {
    return super.getModelElement() as CraftTable;
  }

  @override
  CraftLayoutResult? layout(CraftLayoutContext layoutContext) {
    CraftLayoutArea area = layoutContext.getArea();
    CraftRectangle parentBox = area.getBBox().clone();
    double availableWidth = parentBox.getWidth();

    // Resolve columns
    prepareColumns(availableWidth);

    // Populate child renderers if empty (likely not populated by parent)
    if (childRenderers.isEmpty) {
      for (var child in getModelElement().getChildren()) {
        addChild(child.createRendererSubTree()!);
      }
    }

    // Distribute cells into rows
    // This is a simplified grid builder.
    // Real  handles overlapping and rowspanning more robustly.
    buildGrid();

    double curY = parentBox.getY() + parentBox.getHeight();
    double totalHeight = 0;

    // Layout rows
    // We need to determine row heights.
    // To do this, we layout each cell in the row with calculated width and infinite height.

    for (int r = 0; r < rows.length; r++) {
      List<CraftCellRenderer?> row = rows[r];
      double rowHeight = 0;

      // Pass 1: Measure Max Height for cells (including rowspans effectively sets min height for the first row of span)
      for (int c = 0; c < row.length; c++) {
        CraftCellRenderer? cell = row[c];
        if (cell == null || isPlaceholder(r, c)) continue;

        CraftCell cellModel = cell.getModelElement() as CraftCell;

        double cellW = getCellWidth(c, cellModel.colspan);

        CraftLayoutArea cellMeasureArea = CraftLayoutArea(
            area.pageOrdinal(), CraftRectangle(0, 0, cellW, 10000));
        CraftLayoutResult? measureResult =
            cell.layout(CraftLayoutContext(cellMeasureArea));

        if (measureResult != null && measureResult.getOccupiedArea() != null) {
          double h = measureResult.getOccupiedArea()!.getBBox().getHeight();
          rowHeight = max(rowHeight, h);
        }
      }

      // Check for available height
      if (totalHeight + rowHeight > parentBox.getHeight() && r > 0) {
        CraftTableRenderer splitRenderer =
            createSplitRenderer(CraftLayoutResult.PARTIAL)
                as CraftTableRenderer;
        splitRenderer.rows = rows.sublist(0, r);
        splitRenderer._populateChildRenderersFromRows();

        CraftTableRenderer overflowRenderer =
            createOverflowRenderer(CraftLayoutResult.PARTIAL)
                as CraftTableRenderer;
        overflowRenderer.rows = rows.sublist(r);
        overflowRenderer._populateChildRenderersFromRows();

        occupiedArea = CraftLayoutArea(
            area.pageOrdinal(),
            CraftRectangle(
                parentBox.getX(),
                parentBox.getY() + parentBox.getHeight() - totalHeight,
                parentBox.getWidth(),
                totalHeight));
        return CraftLayoutResult(CraftLayoutResult.PARTIAL, occupiedArea,
            splitRenderer, overflowRenderer);
      }

      // Pass 2: Set final rects for this row
      double currentColX = 0;
      for (int c = 0; c < columns!.length; c++) {
        if (c >= row.length) break;
        CraftCellRenderer? cell = row[c];
        double colW = columns![c];

        if (cell != null && !isPlaceholder(r, c)) {
          CraftCell cellModel = cell.getModelElement() as CraftCell;
          double cellW = getCellWidth(c, cellModel.colspan);
          double cellH = rowHeight;

          CraftLayoutArea finalArea = CraftLayoutArea(
              area.pageOrdinal(),
              CraftRectangle(
                  parentBox.getX() + currentColX, curY - cellH, cellW, cellH));
          cell.layout(CraftLayoutContext(finalArea));
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

    occupiedArea = CraftLayoutArea(
        area.pageOrdinal(),
        CraftRectangle(
            parentBox.getX(),
            parentBox.getY() + parentBox.getHeight() - totalHeight,
            tableWidth,
            totalHeight));

    return CraftLayoutResult(CraftLayoutResult.FULL, occupiedArea, null, null);
  }

  void prepareColumns(double availableWidth) {
    if (columns != null) return;
    CraftTable table = getModelElement();
    List<CraftUnitValue>? definedWidths = table.columnWidths;

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

    for (CraftRenderer child in childRenderers) {
      if (child is CraftCellRenderer) {
        CraftCell cellModel = child.getModelElement() as CraftCell;
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
  Future<void> draw(CraftDrawContext drawContext) async {
    await super.draw(drawContext);
    // Borders are drawn by CellRenderers?
    // AbstractRenderer.drawBorder draws individual borders.
    // Table border?
  }

  @override
  CraftRenderer getNextRenderer() {
    return CraftTableRenderer(getModelElement());
  }

  @override
  CraftAbstractRenderer createSplitRenderer(int layoutResult) {
    CraftTableRenderer splitRenderer = getNextRenderer() as CraftTableRenderer;
    splitRenderer.modelElement = modelElement;
    splitRenderer.parent = parent;
    splitRenderer.columns = columns;
    return splitRenderer;
  }

  @override
  CraftAbstractRenderer createOverflowRenderer(int layoutResult) {
    CraftTableRenderer overflowRenderer =
        getNextRenderer() as CraftTableRenderer;
    overflowRenderer.modelElement = modelElement;
    overflowRenderer.parent = parent;
    overflowRenderer.columns = columns;
    return overflowRenderer;
  }

  void _populateChildRenderersFromRows() {
    childRenderers.clear();
    Set<CraftRenderer> uniqueChildren = {};
    for (var row in rows) {
      for (var cell in row) {
        if (cell != null) {
          if (cell is _CellPlaceholder) {
            uniqueChildren.add(cell.origin);
          } else {
            uniqueChildren.add(cell);
          }
        }
      }
    }
    childRenderers.addAll(uniqueChildren);
  }
}

class _CellPlaceholder extends CraftCellRenderer {
  final CraftCellRenderer origin;
  _CellPlaceholder(this.origin) : super(origin.getModelElement() as CraftCell);
}
