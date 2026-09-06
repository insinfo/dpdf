import 'package:test/test.dart';
import 'package:pdfcraft/src/io/font/true_type_font.dart';
import 'package:pdfcraft/src/kernel/font/pdf_true_type_font.dart';
import 'package:pdfcraft/src/kernel/geom/rectangle.dart';
import 'package:pdfcraft/src/layout/element/text.dart';
import 'package:pdfcraft/src/layout/renderer/text_renderer.dart';
import 'package:pdfcraft/src/layout/layout/layout_context.dart';
import 'package:pdfcraft/src/layout/layout/layout_area.dart';
import 'package:pdfcraft/src/layout/layout/layout_result.dart';
import 'package:pdfcraft/src/layout/properties/property.dart';
import 'package:pdfcraft/src/layout/properties/unit_value.dart';
import 'package:pdfcraft/src/layout/minmaxwidth/min_max_width.dart';

void main() {
  group('TextLayout Test', () {
    test('Simple layout - no split', () async {
      final ttf =
          CraftTrueTypeFont.fromFile(r"test/assets/ABeeZee-Regular.ttf");
      final font = CraftPdfTrueTypeFont(ttf);

      final textElement = CraftText("Hello World");
      textElement.setProperty(CraftProperty.FONT, font);
      textElement.setProperty(
          CraftProperty.FONT_SIZE, CraftUnitValue.createPointValue(12));

      final renderer = CraftTextRenderer(textElement);

      // Layout context with plenty of space
      final area = CraftLayoutArea(1, CraftRectangle(0, 0, 200, 100));
      final result = renderer.layout(CraftLayoutContext(area));

      expect(result, isNotNull);
      expect(result!.getStatus(), equals(CraftLayoutResult.FULL));
      expect(result.getOccupiedArea(), isNotNull);
      // "Hello World" width approx 60-70 pts at 12pt
      expect(result.getOccupiedArea()!.getBBox().getWidth(), greaterThan(50));
      expect(result.getOccupiedArea()!.getBBox().getWidth(), lessThan(100));
    });

    test('Simple layout - forced split', () async {
      final ttf =
          CraftTrueTypeFont.fromFile(r"test/assets/ABeeZee-Regular.ttf");
      final font = CraftPdfTrueTypeFont(ttf);

      final textElement = CraftText("Hello World");
      textElement.setProperty(CraftProperty.FONT, font);
      textElement.setProperty(
          CraftProperty.FONT_SIZE, CraftUnitValue.createPointValue(12));

      final renderer = CraftTextRenderer(textElement);

      // Layout context with limited space, should split "Hello " and "World" or similar
      // "Hello World" is about 65 width. Let's give 40. "Hello" is ~30.
      final area = CraftLayoutArea(1, CraftRectangle(0, 0, 40, 100));
      final result = renderer.layout(CraftLayoutContext(area));

      expect(result, isNotNull);
      expect(result!.getStatus(), equals(CraftLayoutResult.PARTIAL));
      expect(result.getSplitRenderer(), isNotNull);
      expect(result.getOverflowRenderer(), isNotNull);

      final splitRenderer = result.getSplitRenderer() as CraftTextRenderer;
      final overflowRenderer =
          result.getOverflowRenderer() as CraftTextRenderer;

      expect(splitRenderer.text, contains("Hell"));
      expect(overflowRenderer.text, isNotEmpty);
    });

    test('Layout with margins', () async {
      final ttf =
          CraftTrueTypeFont.fromFile(r"test/assets/ABeeZee-Regular.ttf");
      final font = CraftPdfTrueTypeFont(ttf);

      final textElement = CraftText("Margins");
      textElement.setProperty(CraftProperty.FONT, font);
      textElement.setProperty(
          CraftProperty.FONT_SIZE, CraftUnitValue.createPointValue(10));
      textElement.setProperty(
          CraftProperty.MARGIN_LEFT, CraftUnitValue.createPointValue(10));
      textElement.setProperty(
          CraftProperty.MARGIN_RIGHT, CraftUnitValue.createPointValue(10));
      textElement.setProperty(
          CraftProperty.MARGIN_TOP, CraftUnitValue.createPointValue(5));
      textElement.setProperty(
          CraftProperty.MARGIN_BOTTOM, CraftUnitValue.createPointValue(5));

      final renderer = CraftTextRenderer(textElement);
      final area = CraftLayoutArea(1, CraftRectangle(0, 0, 200, 100));
      final result = renderer.layout(CraftLayoutContext(area));

      expect(result, isNotNull);
      expect(result!.getStatus(), equals(CraftLayoutResult.FULL));
      CraftRectangle occ = result.getOccupiedArea()!.getBBox();

      expect(occ.getWidth(), greaterThan(40)); // Text width (~35) + 20
      expect(
          occ.getHeight(), closeTo(20, 0.1)); // 10 font size + 5 top + 5 bottom
      expect(occ.getWidth(), greaterThan(40)); // Text width (~35) + 20
      expect(
          occ.getHeight(), closeTo(20, 0.1)); // 10 font size + 5 top + 5 bottom
    });

    test('MinMaxWidth calculation', () async {
      final ttf =
          CraftTrueTypeFont.fromFile(r"test/assets/ABeeZee-Regular.ttf");
      final font = CraftPdfTrueTypeFont(ttf);

      final textElement = CraftText("Hello World");
      textElement.setProperty(CraftProperty.FONT, font);
      textElement.setProperty(
          CraftProperty.FONT_SIZE, CraftUnitValue.createPointValue(10));

      final renderer = CraftTextRenderer(textElement);
      CraftMinMaxWidth? mmw = renderer.getMinMaxWidth();
      expect(mmw, isNotNull);

      expect(mmw!.getMinWidth(), greaterThan(20));
      expect(mmw.getMaxWidth(), greaterThan(mmw.getMinWidth()));
    });
  });
}
