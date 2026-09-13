import 'package:test/test.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/element/cell.dart';
import 'package:dpdf/src/layout/element/div.dart';
import 'package:dpdf/src/layout/element/table.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/renderer/table_renderer.dart';

Cell _cell(double height, [int rowspan = 1, int colspan = 1]) {
  final cell = Cell(rowspan, colspan);
  cell.add(Div()..setMinHeight(height));
  return cell;
}

Table _twoColumnTable() =>
    Table(List.filled(2, UnitValue.createPointValue(100)));

TableRenderer _renderer(Table table) {
  final renderer = TableRenderer(table);
  for (final child in table.getChildren()) {
    renderer.addChild(child.createRendererSubTree()!);
  }
  return renderer;
}

void main() {
  test('a repeated header is measured and placed on the area', () {
    final table = _twoColumnTable()
      ..addHeaderCell(_cell(20))
      ..addHeaderCell(_cell(20))
      ..addCell(_cell(30))
      ..addCell(_cell(30));

    final renderer = _renderer(table);
    final result = renderer
        .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 500))));

    expect(result!.getStatus(), LayoutResult.FULL);
    expect(renderer.headerRows.length, 1);
    expect(result.getOccupiedArea()!.getBBox().getHeight(), 50);
  });

  test('header cells are tagged as TH and body cells as TD', () {
    final header = _cell(20);
    final body = _cell(20);
    _twoColumnTable()
      ..addHeaderCell(header)
      ..addCell(body);
    expect(header.isHeader, isTrue);
    expect(header.getAccessibilityProperties().getRole(), 'TH');
    expect(body.getAccessibilityProperties().getRole(), 'TD');
  });

  test('the header is repeated on the overflow renderer', () {
    final table = _twoColumnTable()..addHeaderCell(_cell(20));
    for (int i = 0; i < 6; i++) {
      table.addCell(_cell(40));
      table.addCell(_cell(40));
    }

    final renderer = _renderer(table);
    final result = renderer
        .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 140))));

    expect(result!.getStatus(), LayoutResult.PARTIAL);
    final overflow = result.getOverflowRenderer() as TableRenderer;
    // The continuation rebuilds the header from the model on its own area.
    overflow.layout(LayoutContext(LayoutArea(2, Rectangle(0, 0, 200, 500))));
    expect(overflow.headerRows.length, 1);
    expect(overflow.isSplitContinuation, isTrue);
  });

  test('the footer is placed after the rows of every area', () {
    final table = _twoColumnTable()
      ..addFooterCell(_cell(15))
      ..addCell(_cell(30))
      ..addCell(_cell(30));

    final renderer = _renderer(table);
    final result = renderer
        .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 500))));

    expect(result!.getStatus(), LayoutResult.FULL);
    expect(renderer.footerRows.length, 1);
    expect(result.getOccupiedArea()!.getBBox().getHeight(), 45);
  });

  test('IGNORE_HEADER suppresses the repeated header', () {
    final table = _twoColumnTable()
      ..addHeaderCell(_cell(20))
      ..addCell(_cell(30))
      ..addCell(_cell(30));
    table.setSkipFirstHeader(true);

    final renderer = _renderer(table);
    final result = renderer
        .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 500))));
    expect(result!.getOccupiedArea()!.getBBox().getHeight(), 30);
  });

  test('a rowspan taller than its rows grows all of them', () {
    final table = _twoColumnTable()
      ..addCell(_cell(100, 2))
      ..addCell(_cell(10))
      ..addCell(_cell(10));

    final renderer = _renderer(table);
    final result = renderer
        .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 500))));

    // The spanning cell needs 100pt over two rows of 10pt each: both rows grow.
    expect(result!.getOccupiedArea()!.getBBox().getHeight(), 100);
  });

  test('a colspan cell covers the width of the spanned columns', () {
    final table = _twoColumnTable()..addCell(_cell(20, 1, 2));
    final renderer = _renderer(table);
    renderer.layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 500))));
    expect(renderer.getCellWidth(0, 2), 200);
  });

  test('a table split never cuts through a vertical span', () {
    final table = _twoColumnTable()
      ..addCell(_cell(20))
      ..addCell(_cell(20))
      ..addCell(_cell(80, 2))
      ..addCell(_cell(20))
      ..addCell(_cell(20));

    final renderer = _renderer(table);
    renderer.layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 1000))));
    // Row 2 is covered by the placeholder of the spanning cell started on row 1.
    expect(renderer.crossesRowspan(2), isTrue);
    expect(renderer.adjustSplitRow(2), 1);
  });

  test('auto columns share the remaining width', () {
    final table = Table([
      UnitValue.createPointValue(120),
      UnitValue.createPointValue(0),
      UnitValue.createPointValue(0),
    ])
      ..addCell(_cell(10));
    final renderer = _renderer(table);
    renderer.prepareColumns(320);
    expect(renderer.columns, [120, 100, 100]);
  });

  test('keep-together keeps a table out of a too small area', () {
    final table = _twoColumnTable();
    for (int i = 0; i < 6; i++) {
      table.addCell(_cell(40));
      table.addCell(_cell(40));
    }
    table.setProperty(Property.KEEP_TOGETHER, true);

    final renderer = _renderer(table);
    final result = renderer
        .layout(LayoutContext(LayoutArea(1, Rectangle(0, 0, 200, 100))));
    expect(result!.getStatus(), LayoutResult.NOTHING);
  });
}
