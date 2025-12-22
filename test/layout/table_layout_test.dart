import 'package:test/test.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/table.dart';
import 'package:dpdf/src/layout/element/cell.dart';
import 'package:dpdf/src/layout/renderer/table_renderer.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/borders/border.dart';

void main() {
  test('TableRenderer Layout Basic', () {
    final ttf =
        TrueTypeFont.fromFile(r"C:\MyDartProjects\itext\test\assets\arial.ttf");
    final font = PdfTrueTypeFont(ttf);

    Table table = Table(List.filled(2, UnitValue.createPointValue(100)));

    Cell c1 = Cell();
    Paragraph p1 = Paragraph("Cell 1");
    p1.setProperty(Property.FONT, font);
    c1.add(p1);
    c1.setProperty(Property.BORDER_BOTTOM, SolidBorder(1));

    Cell c2 = Cell();
    Paragraph p2 = Paragraph("Cell 2");
    p2.setProperty(Property.FONT, font);
    c2.add(p2);

    table.addCell(c1);
    table.addCell(c2);

    Cell c3 = Cell();
    Paragraph p3 = Paragraph("Row 2 Col 1");
    p3.setProperty(Property.FONT, font);
    c3.add(p3);
    table.addCell(c3);

    Cell c4 = Cell();
    Paragraph p4 = Paragraph("Row 2 Col 2");
    p4.setProperty(Property.FONT, font);
    c4.add(p4);
    table.addCell(c4);

    TableRenderer renderer = TableRenderer(table);
    // Simulate adding children manually or rely on DocumentRenderer structure
    // Usually Renderers are created recursively.
    // TableRenderer layout usually creates child renderers if not present?
    // BlockRenderer doesn't auto-create.
    // We must manually populate child renderers for this unit test or use a helper.

    for (var child in table.getChildren()) {
      renderer.addChild(child.createRendererSubTree()!);
    }

    LayoutArea area = LayoutArea(1, Rectangle(0, 0, 500, 500));
    renderer.layout(LayoutContext(area));

    expect(renderer.occupiedArea, isNotNull);
    print("Table Height: ${renderer.occupiedArea!.getBBox().getHeight()}");

    expect(renderer.occupiedArea!.getBBox().getHeight(),
        greaterThan(20)); // At least 2 lines of text
    expect(renderer.occupiedArea!.getBBox().getWidth(),
        closeTo(200, 1.0)); // 2 columns of 100
  });

  test('TableRenderer Layout Spans', () {
    final ttf =
        TrueTypeFont.fromFile(r"C:\MyDartProjects\itext\test\assets\arial.ttf");
    final font = PdfTrueTypeFont(ttf);

    // 3 columns
    Table table = Table(List.filled(3, UnitValue.createPointValue(100)));

    // Row 1: 1 col, 2 col span
    Cell c1 = Cell(1, 1).add(Paragraph("1,1").setFont(font));
    Cell c2 = Cell(1, 2).add(Paragraph("1,2-3").setFont(font));
    table.addCell(c1).addCell(c2);

    // Row 2: 2 row span, 1 col, 1 col
    Cell c3 = Cell(2, 1).add(Paragraph("2-3,1").setFont(font));
    Cell c4 = Cell(1, 1).add(Paragraph("2,2").setFont(font));
    Cell c5 = Cell(1, 1).add(Paragraph("2,3").setFont(font));
    table.addCell(c3).addCell(c4).addCell(c5);

    // Row 3: (skipped col 1 due to rowspan), 2 col span
    Cell c6 = Cell(1, 2).add(Paragraph("3,2-3").setFont(font));
    table.addCell(c6);

    TableRenderer renderer = TableRenderer(table);
    for (var child in table.getChildren()) {
      renderer.addChild(child.createRendererSubTree()!);
    }

    LayoutArea area = LayoutArea(1, Rectangle(0, 0, 500, 500));
    renderer.layout(LayoutContext(area));

    expect(renderer.occupiedArea, isNotNull);
    print(
        "Table with spans Height: ${renderer.occupiedArea!.getBBox().getHeight()}");

    // Check occupied area width
    expect(renderer.occupiedArea!.getBBox().getWidth(), closeTo(300, 1.0));
  });

  test('TableRenderer Layout Splitting', () {
    final ttf =
        TrueTypeFont.fromFile(r"C:\MyDartProjects\itext\test\assets\arial.ttf");
    final font = PdfTrueTypeFont(ttf);

    Table table = Table(List.filled(1, UnitValue.createPointValue(300)));
    for (int i = 1; i <= 10; i++) {
      table.addCell(Cell().add(Paragraph("Row $i").setFont(font)));
    }

    TableRenderer renderer = TableRenderer(table);
    for (var child in table.getChildren()) {
      renderer.addChild(child.createRendererSubTree()!);
    }

    // Area that only fits about 4-5 rows (each row height ~13pt)
    LayoutArea area = LayoutArea(1, Rectangle(0, 0, 500, 60));
    LayoutResult? result = renderer.layout(LayoutContext(area));

    expect(result, isNotNull);
    final r = result!;
    expect(r.getStatus(), equals(LayoutResult.PARTIAL));
    expect(r.getSplitRenderer(), isNotNull);
    expect(r.getOverflowRenderer(), isNotNull);

    TableRenderer split = r.getSplitRenderer() as TableRenderer;
    TableRenderer overflow = r.getOverflowRenderer() as TableRenderer;

    print("Split rows: ${split.rows.length}");
    print("Overflow rows: ${overflow.rows.length}");

    expect(split.rows.length, greaterThan(0));
    expect(overflow.rows.length, greaterThan(0));
    expect(split.rows.length + overflow.rows.length, equals(10));
  });
}
