import 'package:test/test.dart';
import 'package:pdfcraft/src/layout/element/paragraph.dart';
import 'package:pdfcraft/src/layout/element/text.dart';
import 'package:pdfcraft/src/layout/renderer/block_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/text_renderer.dart';
import 'package:pdfcraft/src/layout/properties/property.dart';
import 'package:pdfcraft/src/layout/properties/unit_value.dart';
import 'package:pdfcraft/src/kernel/font/pdf_true_type_font.dart';
import 'package:pdfcraft/src/io/font/true_type_font.dart';
import 'package:pdfcraft/src/layout/minmaxwidth/min_max_width.dart';

void main() {
  test('BlockRenderer MinMaxWidth', () {
    final ttf = CraftTrueTypeFont.fromFile(r"test/assets/ABeeZee-Regular.ttf");
    final font = CraftPdfTrueTypeFont(ttf);

    CraftParagraph p = CraftParagraph();
    CraftText t1 = CraftText("Hello");
    t1.setProperty(CraftProperty.FONT, font);
    t1.setProperty(
        CraftProperty.FONT_SIZE, CraftUnitValue.createPointValue(10));

    CraftText t2 = CraftText("WorldLonger");
    t2.setProperty(CraftProperty.FONT, font);
    t2.setProperty(
        CraftProperty.FONT_SIZE, CraftUnitValue.createPointValue(10));

    p.add(t1);
    p.add(t2);

    CraftBlockRenderer renderer = CraftBlockRenderer(p);

    // Manually add child renderers
    renderer.addChild(CraftTextRenderer(t1));
    renderer.addChild(CraftTextRenderer(t2));

    CraftMinMaxWidth? mmw = renderer.getMinMaxWidth();
    expect(mmw, isNotNull);

    // Block min should be max of children mins (stacking)
    expect(mmw!.getMinWidth(), greaterThan(40));
  });
}
