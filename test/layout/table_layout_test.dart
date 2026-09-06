import 'package:test/test.dart';
import 'package:pdfcraft/src/layout/element/paragraph.dart';
import 'package:pdfcraft/src/layout/element/table.dart';
import 'package:pdfcraft/src/layout/element/cell.dart';
import 'package:pdfcraft/src/layout/renderer/table_renderer.dart';
import 'package:pdfcraft/src/layout/properties/property.dart';
import 'package:pdfcraft/src/layout/properties/unit_value.dart';
import 'package:pdfcraft/src/kernel/font/pdf_true_type_font.dart';
import 'package:pdfcraft/src/io/font/true_type_font.dart';
import 'package:pdfcraft/src/layout/layout/layout_context.dart';
import 'package:pdfcraft/src/layout/layout/layout_result.dart';
import 'package:pdfcraft/src/layout/layout/layout_area.dart';
import 'package:pdfcraft/src/kernel/geom/rectangle.dart';
import 'package:pdfcraft/src/layout/borders/border.dart';

void main() {
  test('TableRenderer Layout Basic', () {
    final ttf = CraftTrueTypeFont.fromFile(r"test/assets/ABeeZee-Regular.ttf");
    final font = CraftPdfTrueTypeFont(ttf);

    CraftTable table =
        CraftTable(List.filled(2, CraftUnitValue.createPointValue(100)));

    CraftCell c1 = CraftCell();
    CraftParagraph p1 = CraftParagraph("Cell 1");
    p1.setProperty(CraftProperty.FONT, font);
    c1.add(p1);
    c1.setProperty(CraftProperty.BORDER_BOTTOM, CraftSolidBorder(1));

    CraftCell c2 = CraftCell();
    CraftParagraph p2 = CraftParagraph("Cell 2");
    p2.setProperty(CraftProperty.FONT, font);
    c2.add(p2);

    table.addCell(c1);
    table.addCell(c2);

    CraftCell c3 = CraftCell();
    CraftParagraph p3 = CraftParagraph("Row 2 Col 1");
    p3.setProperty(CraftProperty.FONT, font);
    c3.add(p3);
    table.addCell(c3);

    CraftCell c4 = CraftCell();
    CraftParagraph p4 = CraftParagraph("Row 2 Col 2");
    p4.setProperty(CraftProperty.FONT, font);
    c4.add(p4);
    table.addCell(c4);

    CraftTableRenderer renderer = CraftTableRenderer(table);
    // Simulate adding children manually or rely on DocumentRenderer structure
    // Usually Renderers are created recursively.
    // TableRenderer layout usually creates child renderers if not present?
    // BlockRenderer doesn't auto-create.
    // We must manually populate child renderers for this unit test or use a helper.

    for (var child in table.getChildren()) {
      renderer.addChild(child.createRendererSubTree()!);
    }

    CraftLayoutArea area = CraftLayoutArea(1, CraftRectangle(0, 0, 500, 500));
    renderer.layout(CraftLayoutContext(area));

    expect(renderer.occupiedArea, isNotNull);

    expect(renderer.occupiedArea!.getBBox().getHeight(),
        greaterThan(20)); // At least 2 lines of text
    expect(renderer.occupiedArea!.getBBox().getWidth(),
        closeTo(200, 1.0)); // 2 columns of 100
  });

  test('TableRenderer Layout Spans', () {
    final ttf = CraftTrueTypeFont.fromFile(r"test/assets/ABeeZee-Regular.ttf");
    final font = CraftPdfTrueTypeFont(ttf);

    // 3 columns
    CraftTable table =
        CraftTable(List.filled(3, CraftUnitValue.createPointValue(100)));

    // Row 1: 1 col, 2 col span
    CraftCell c1 = CraftCell(1, 1).add(CraftParagraph("1,1").setFont(font));
    CraftCell c2 = CraftCell(1, 2).add(CraftParagraph("1,2-3").setFont(font));
    table.addCell(c1).addCell(c2);

    // Row 2: 2 row span, 1 col, 1 col
    CraftCell c3 = CraftCell(2, 1).add(CraftParagraph("2-3,1").setFont(font));
    CraftCell c4 = CraftCell(1, 1).add(CraftParagraph("2,2").setFont(font));
    CraftCell c5 = CraftCell(1, 1).add(CraftParagraph("2,3").setFont(font));
    table.addCell(c3).addCell(c4).addCell(c5);

    // Row 3: (skipped col 1 due to rowspan), 2 col span
    CraftCell c6 = CraftCell(1, 2).add(CraftParagraph("3,2-3").setFont(font));
    table.addCell(c6);

    CraftTableRenderer renderer = CraftTableRenderer(table);
    for (var child in table.getChildren()) {
      renderer.addChild(child.createRendererSubTree()!);
    }

    CraftLayoutArea area = CraftLayoutArea(1, CraftRectangle(0, 0, 500, 500));
    renderer.layout(CraftLayoutContext(area));

    expect(renderer.occupiedArea, isNotNull);

    // Check occupied area width
    expect(renderer.occupiedArea!.getBBox().getWidth(), closeTo(300, 1.0));
  });

  test('TableRenderer Layout Splitting', () {
    final ttf = CraftTrueTypeFont.fromFile(r"test/assets/ABeeZee-Regular.ttf");
    final font = CraftPdfTrueTypeFont(ttf);

    CraftTable table =
        CraftTable(List.filled(1, CraftUnitValue.createPointValue(300)));
    for (int i = 1; i <= 10; i++) {
      table.addCell(CraftCell().add(CraftParagraph("Row $i").setFont(font)));
    }

    CraftTableRenderer renderer = CraftTableRenderer(table);
    for (var child in table.getChildren()) {
      renderer.addChild(child.createRendererSubTree()!);
    }

    // Area that only fits about 4-5 rows (each row height ~13pt)
    CraftLayoutArea area = CraftLayoutArea(1, CraftRectangle(0, 0, 500, 60));
    CraftLayoutResult? result = renderer.layout(CraftLayoutContext(area));

    expect(result, isNotNull);
    final r = result!;
    expect(r.getStatus(), equals(CraftLayoutResult.PARTIAL));
    expect(r.getSplitRenderer(), isNotNull);
    expect(r.getOverflowRenderer(), isNotNull);

    CraftTableRenderer split = r.getSplitRenderer() as CraftTableRenderer;
    CraftTableRenderer overflow = r.getOverflowRenderer() as CraftTableRenderer;

    expect(split.rows.length, greaterThan(0));
    expect(overflow.rows.length, greaterThan(0));
    expect(split.rows.length + overflow.rows.length, equals(10));
  });
}
