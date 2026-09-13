import 'dart:math';

import 'package:dpdf/src/layout/renderer/abstract_renderer.dart';
import 'package:dpdf/src/layout/element/table.dart';
import 'package:dpdf/src/layout/element/cell.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/renderer/draw_context.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/renderer/renderer.dart';
import 'package:dpdf/src/layout/renderer/cell_renderer.dart';

class TableRenderer extends AbstractRenderer {
  List<double>? columns;
  List<List<CellRenderer?>> rows = [];

  /// Header rows repeated on every area the table spans.
  List<List<CellRenderer?>> headerRows = [];

  /// Footer rows repeated on every area the table spans.
  List<List<CellRenderer?>> footerRows = [];

  /// Set on the overflow renderer so that the repeated header is rebuilt.
  bool isSplitContinuation = false;

  TableRenderer(Table super.modelElement);

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

    // Populate child renderers if empty (likely not populated by parent)
    if (childRenderers.isEmpty) {
      for (var child in getModelElement().getChildren()) {
        addChild(child.createRendererSubTree()!);
      }
    }

    // Distribute cells into rows
    buildGrid();
    buildHeaderAndFooter();

    final bool skipHeader = getProperty<bool>(Property.IGNORE_HEADER) == true;
    final bool skipFooter = getProperty<bool>(Property.IGNORE_FOOTER) == true;

    final List<double> headerHeights = skipHeader
        ? const <double>[]
        : measureRowHeights(headerRows, area.pageOrdinal());
    final List<double> footerHeights = skipFooter
        ? const <double>[]
        : measureRowHeights(footerRows, area.pageOrdinal());
    final List<double> bodyHeights =
        measureRowHeights(rows, area.pageOrdinal());

    final double headerHeight = headerHeights.fold(0.0, (a, b) => a + b);
    final double footerHeight = footerHeights.fold(0.0, (a, b) => a + b);

    double curY = parentBox.getY() + parentBox.getHeight();
    double totalHeight = 0;

    // Header is placed first on every area.
    if (headerHeight > 0) {
      placeRows(headerRows, headerHeights, parentBox, curY, area.pageOrdinal());
      curY -= headerHeight;
      totalHeight += headerHeight;
    }

    final double bodyLimit =
        parentBox.getHeight() - headerHeight - footerHeight;
    double bodyUsed = 0;
    int placedRows = rows.length;
    for (int r = 0; r < rows.length; r++) {
      if (bodyUsed + bodyHeights[r] > bodyLimit && r > 0) {
        placedRows = adjustSplitRow(r);
        break;
      }
      bodyUsed += bodyHeights[r];
    }

    if (placedRows < rows.length) {
      if (getProperty<bool>(Property.KEEP_TOGETHER) == true &&
          getProperty<bool>(Property.FORCED_PLACEMENT) != true) {
        return LayoutResult(LayoutResult.NOTHING, null, null,
            createOverflowRendererForRows(rows), this);
      }
      final splitBody = rows.sublist(0, placedRows);
      final splitHeights = bodyHeights.sublist(0, placedRows);
      placeRows(splitBody, splitHeights, parentBox, curY, area.pageOrdinal());
      double splitBodyHeight = splitHeights.fold(0.0, (a, b) => a + b);
      curY -= splitBodyHeight;
      totalHeight += splitBodyHeight;

      if (footerHeight > 0) {
        placeRows(
            footerRows, footerHeights, parentBox, curY, area.pageOrdinal());
        totalHeight += footerHeight;
      }

      TableRenderer splitRenderer =
          createSplitRenderer(LayoutResult.PARTIAL) as TableRenderer;
      splitRenderer.rows = splitBody;
      splitRenderer.headerRows = headerRows;
      splitRenderer.footerRows = footerRows;
      splitRenderer._populateChildRenderersFromRows();

      TableRenderer overflowRenderer =
          createOverflowRenderer(LayoutResult.PARTIAL) as TableRenderer;
      overflowRenderer.rows = rows.sublist(placedRows);
      overflowRenderer.isSplitContinuation = true;
      overflowRenderer._populateChildRenderersFromRows();

      occupiedArea = LayoutArea(
          area.pageOrdinal(),
          Rectangle(
              parentBox.getX(),
              parentBox.getY() + parentBox.getHeight() - totalHeight,
              tableWidth(availableWidth),
              totalHeight));
      splitRenderer.occupiedArea = occupiedArea;
      return LayoutResult(
          LayoutResult.PARTIAL, occupiedArea, splitRenderer, overflowRenderer);
    }

    placeRows(rows, bodyHeights, parentBox, curY, area.pageOrdinal());
    curY -= bodyUsed;
    totalHeight += bodyUsed;

    if (footerHeight > 0) {
      placeRows(footerRows, footerHeights, parentBox, curY, area.pageOrdinal());
      totalHeight += footerHeight;
    }

    occupiedArea = LayoutArea(
        area.pageOrdinal(),
        Rectangle(
            parentBox.getX(),
            parentBox.getY() + parentBox.getHeight() - totalHeight,
            tableWidth(availableWidth),
            totalHeight));

    return LayoutResult(LayoutResult.FULL, occupiedArea, null, null);
  }

  double tableWidth(double availableWidth) {
    if (columns == null) return availableWidth;
    double tableWidth = 0;
    for (var w in columns!) {
      tableWidth += w;
    }
    return tableWidth;
  }

  /// Never break a table in the middle of a vertically spanning cell: the split
  /// is moved up to the first row where no rowspan crosses the boundary.
  int adjustSplitRow(int requestedRow) {
    int splitRow = requestedRow;
    while (splitRow > 0 && crossesRowspan(splitRow)) {
      splitRow--;
    }
    return splitRow == 0 ? requestedRow : splitRow;
  }

  bool crossesRowspan(int rowIndex) {
    if (rowIndex <= 0 || rowIndex >= rows.length) return false;
    for (int c = 0; c < rows[rowIndex].length; c++) {
      if (rows[rowIndex][c] is _CellPlaceholder) return true;
    }
    return false;
  }

  /// Measures every row of [grid], honouring rowspan by distributing the extra
  /// height of a spanning cell over the rows it covers.
  List<double> measureRowHeights(
      List<List<CellRenderer?>> grid, int pageNumber) {
    final heights = List<double>.filled(grid.length, 0);
    final spanning = <List<int>>[];
    final spanningHeights = <double>[];

    for (int r = 0; r < grid.length; r++) {
      final row = grid[r];
      for (int c = 0; c < row.length; c++) {
        final cell = row[c];
        if (cell == null || cell is _CellPlaceholder) continue;
        final cellModel = cell.getModelElement() as Cell;
        final cellW = getCellWidth(c, cellModel.colspan);
        final measureArea =
            LayoutArea(pageNumber, Rectangle(0, 0, cellW, 100000));
        final measureResult = cell.layout(LayoutContext(measureArea));
        final h = measureResult?.getOccupiedArea()?.getBBox().getHeight() ?? 0;
        final rowspan = min(cellModel.rowspan, grid.length - r);
        if (rowspan <= 1) {
          heights[r] = max(heights[r], h);
        } else {
          spanning.add([r, rowspan]);
          spanningHeights.add(h);
        }
      }
    }

    for (int i = 0; i < spanning.length; i++) {
      final start = spanning[i][0];
      final span = spanning[i][1];
      double covered = 0;
      for (int r = start; r < start + span; r++) {
        covered += heights[r];
      }
      final deficit = spanningHeights[i] - covered;
      if (deficit > 0) {
        final share = deficit / span;
        for (int r = start; r < start + span; r++) {
          heights[r] += share;
        }
      }
    }
    return heights;
  }

  /// Assigns the final rectangles of every cell of [grid].
  void placeRows(List<List<CellRenderer?>> grid, List<double> heights,
      Rectangle parentBox, double topY, int pageNumber) {
    double curY = topY;
    for (int r = 0; r < grid.length; r++) {
      double currentColX = 0;
      for (int c = 0; c < columns!.length; c++) {
        if (c >= grid[r].length) break;
        final cell = grid[r][c];
        final colW = columns![c];
        if (cell != null && cell is! _CellPlaceholder) {
          final cellModel = cell.getModelElement() as Cell;
          final cellW = getCellWidth(c, cellModel.colspan);
          double cellH = 0;
          final rowspan = min(cellModel.rowspan, grid.length - r);
          for (int i = 0; i < rowspan; i++) {
            cellH += heights[r + i];
          }
          final finalArea = LayoutArea(
              pageNumber,
              Rectangle(
                  parentBox.getX() + currentColX, curY - cellH, cellW, cellH));
          // The row height already accommodates the measured content, so the
          // cell must never refuse the placement it is given.
          cell.setProperty(Property.FORCED_PLACEMENT, true);
          cell.layout(LayoutContext(finalArea));
          cell.occupiedArea = LayoutArea(
              pageNumber,
              Rectangle(
                  parentBox.getX() + currentColX, curY - cellH, cellW, cellH));
        }
        currentColX += colW;
      }
      curY -= heights[r];
    }
  }

  void prepareColumns(double availableWidth) {
    if (columns != null) return;
    Table table = getModelElement();
    List<UnitValue>? definedWidths = table.columnWidths;

    if (definedWidths == null || definedWidths.isEmpty) {
      columns = [availableWidth];
      return;
    }

    columns = [];
    final autoIndexes = <int>[];
    double totalDefined = 0;

    for (int i = 0; i < definedWidths.length; i++) {
      final uv = definedWidths[i];
      if (uv.isPointValue() && uv.getValue() > 0) {
        columns!.add(uv.getValue());
        totalDefined += uv.getValue();
      } else if (uv.isPercentValue()) {
        double w = availableWidth * uv.getValue() / 100.0;
        columns!.add(w);
        totalDefined += w;
      } else {
        columns!.add(0);
        autoIndexes.add(i);
      }
    }

    // Auto columns share whatever is left of the available width.
    if (autoIndexes.isNotEmpty) {
      final remaining = availableWidth - totalDefined;
      final share = remaining > 0 ? remaining / autoIndexes.length : 0.0;
      for (final index in autoIndexes) {
        columns![index] = share;
      }
    }
  }

  void buildGrid() {
    if (rows.isNotEmpty) return;

    int colCount = columns?.length ?? 1;
    int r = 0;
    int c = 0;

    for (Renderer child in childRenderers) {
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
              rows[rowIdx][colIdx] = _CellPlaceholder(child);
            }
          }
        }
        c += colspan;
      }
    }
  }

  /// Builds (once) the grids of the repeating header and footer rows.
  void buildHeaderAndFooter() {
    final table = getModelElement();
    if (headerRows.isEmpty && table.headerCells.isNotEmpty) {
      headerRows = _buildGridFor(table.headerCells);
    }
    if (footerRows.isEmpty && table.footerCells.isNotEmpty) {
      footerRows = _buildGridFor(table.footerCells);
    }
  }

  List<List<CellRenderer?>> _buildGridFor(List<Cell> cells) {
    final int colCount = columns?.length ?? 1;
    final List<List<CellRenderer?>> grid = [];
    int r = 0;
    int c = 0;
    for (final cellModel in cells) {
      final renderer = cellModel.createRendererSubTree() as CellRenderer;
      renderer.setParent(this);
      int colspan = cellModel.colspan;
      final rowspan = cellModel.rowspan;
      while (true) {
        if (r >= grid.length) grid.add(List.filled(colCount, null));
        if (c >= colCount) {
          r++;
          c = 0;
          continue;
        }
        if (grid[r][c] != null) {
          c++;
          continue;
        }
        break;
      }
      if (c + colspan > colCount) colspan = colCount - c;
      for (int i = 0; i < rowspan; i++) {
        for (int j = 0; j < colspan; j++) {
          while (r + i >= grid.length) {
            grid.add(List.filled(colCount, null));
          }
          grid[r + i][c + j] =
              (i == 0 && j == 0) ? renderer : _CellPlaceholder(renderer);
        }
      }
      c += colspan;
    }
    return grid;
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
    drawBackground(drawContext);
    drawBorder(drawContext);
    for (final row in headerRows) {
      await _drawRow(row, drawContext);
    }
    await drawChildren(drawContext);
    for (final row in footerRows) {
      await _drawRow(row, drawContext);
    }
  }

  Future<void> _drawRow(
      List<CellRenderer?> row, DrawContext drawContext) async {
    for (final cell in row) {
      if (cell != null && cell is! _CellPlaceholder) {
        await cell.draw(drawContext);
      }
    }
  }

  @override
  Renderer getNextRenderer() {
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

  TableRenderer createOverflowRendererForRows(List<List<CellRenderer?>> rows) {
    final overflowRenderer =
        createOverflowRenderer(LayoutResult.NOTHING) as TableRenderer;
    overflowRenderer.rows = rows;
    overflowRenderer._populateChildRenderersFromRows();
    return overflowRenderer;
  }

  void _populateChildRenderersFromRows() {
    childRenderers.clear();
    Set<Renderer> uniqueChildren = {};
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

class _CellPlaceholder extends CellRenderer {
  final CellRenderer origin;
  _CellPlaceholder(this.origin) : super(origin.getModelElement() as Cell);
}
