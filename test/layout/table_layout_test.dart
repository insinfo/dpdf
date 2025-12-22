import 'package:test/test.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/table.dart';
import 'package:dpdf/src/layout/element/cell.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/renderer/table_renderer.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/borders/border.dart';
import 'package:dpdf/src/kernel/colors/device_gray.dart';

void main() {
  test('TableRenderer Layout Basic', () {
    final ttf = TrueTypeFont.fromFile("c:/windows/fonts/arial.ttf");
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
}
