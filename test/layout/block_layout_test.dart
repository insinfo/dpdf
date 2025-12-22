import 'package:test/test.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/renderer/block_renderer.dart';
import 'package:dpdf/src/layout/renderer/text_renderer.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

void main() {
  test('BlockRenderer MinMaxWidth', () {
    final ttf =
        TrueTypeFont.fromFile(r"C:\MyDartProjects\itext\test\assets\arial.ttf");
    final font = PdfTrueTypeFont(ttf);

    Paragraph p = Paragraph();
    Text t1 = Text("Hello");
    t1.setProperty(Property.FONT, font);
    t1.setProperty(Property.FONT_SIZE, UnitValue.createPointValue(10));

    Text t2 = Text("WorldLonger");
    t2.setProperty(Property.FONT, font);
    t2.setProperty(Property.FONT_SIZE, UnitValue.createPointValue(10));

    p.add(t1);
    p.add(t2);

    BlockRenderer renderer = BlockRenderer(p);

    // Manually add child renderers
    renderer.addChild(TextRenderer(t1));
    renderer.addChild(TextRenderer(t2));

    MinMaxWidth? mmw = renderer.getMinMaxWidth();
    expect(mmw, isNotNull);

    print("Block Min: ${mmw!.getMinWidth()}, Max: ${mmw.getMaxWidth()}");

    // Block min should be max of children mins (stacking)
    expect(mmw.getMinWidth(), greaterThan(40));
  });
}
