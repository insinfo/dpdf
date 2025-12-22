import 'package:test/test.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/renderer/text_renderer.dart';
import 'package:dpdf/src/layout/layout/layout_context.dart';
import 'package:dpdf/src/layout/layout/layout_area.dart';
import 'package:dpdf/src/layout/layout/layout_result.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/minmaxwidth/min_max_width.dart';

void main() {
  group('TextLayout Test', () {
    test('Simple layout - no split', () async {
      final ttf = TrueTypeFont.fromFile("c:/windows/fonts/arial.ttf");
      final font = PdfTrueTypeFont(ttf);

      final textElement = Text("Hello World");
      textElement.setProperty(Property.FONT, font);
      textElement.setProperty(
          Property.FONT_SIZE, UnitValue.createPointValue(12));

      final renderer = TextRenderer(textElement);

      // Layout context with plenty of space
      final area = LayoutArea(1, Rectangle(0, 0, 200, 100));
      final result = renderer.layout(LayoutContext(area));

      expect(result, isNotNull);
      expect(result!.getStatus(), equals(LayoutResult.FULL));
      expect(result.getOccupiedArea(), isNotNull);
      // "Hello World" width approx 60-70 pts at 12pt
      expect(result.getOccupiedArea()!.getBBox().getWidth(), greaterThan(50));
      expect(result.getOccupiedArea()!.getBBox().getWidth(), lessThan(100));
    });

    test('Simple layout - forced split', () async {
      final ttf = TrueTypeFont.fromFile("c:/windows/fonts/arial.ttf");
      final font = PdfTrueTypeFont(ttf);

      final textElement = Text("Hello World");
      textElement.setProperty(Property.FONT, font);
      textElement.setProperty(
          Property.FONT_SIZE, UnitValue.createPointValue(12));

      final renderer = TextRenderer(textElement);

      // Layout context with limited space, should split "Hello " and "World" or similar
      // "Hello World" is about 65 width. Let's give 40. "Hello" is ~30.
      final area = LayoutArea(1, Rectangle(0, 0, 40, 100));
      final result = renderer.layout(LayoutContext(area));

      expect(result, isNotNull);
      expect(result!.getStatus(), equals(LayoutResult.PARTIAL));
      expect(result.getSplitRenderer(), isNotNull);
      expect(result.getOverflowRenderer(), isNotNull);

      final splitRenderer = result.getSplitRenderer() as TextRenderer;
      final overflowRenderer = result.getOverflowRenderer() as TextRenderer;

      print("Split text: '${splitRenderer.text}'");
      print("Overflow text: '${overflowRenderer.text}'");

      expect(splitRenderer.text, contains("Hell"));
      expect(overflowRenderer.text, isNotEmpty);
    });

    test('Layout with margins', () async {
      final ttf = TrueTypeFont.fromFile("c:/windows/fonts/arial.ttf");
      final font = PdfTrueTypeFont(ttf);

      final textElement = Text("Margins");
      textElement.setProperty(Property.FONT, font);
      textElement.setProperty(
          Property.FONT_SIZE, UnitValue.createPointValue(10));
      textElement.setProperty(
          Property.MARGIN_LEFT, UnitValue.createPointValue(10));
      textElement.setProperty(
          Property.MARGIN_RIGHT, UnitValue.createPointValue(10));
      textElement.setProperty(
          Property.MARGIN_TOP, UnitValue.createPointValue(5));
      textElement.setProperty(
          Property.MARGIN_BOTTOM, UnitValue.createPointValue(5));

      final renderer = TextRenderer(textElement);
      final area = LayoutArea(1, Rectangle(0, 0, 200, 100));
      final result = renderer.layout(LayoutContext(area));

      expect(result, isNotNull);
      expect(result!.getStatus(), equals(LayoutResult.FULL));
      Rectangle occ = result.getOccupiedArea()!.getBBox();

      expect(occ.getWidth(), greaterThan(40)); // Text width (~35) + 20
      expect(
          occ.getHeight(), closeTo(20, 0.1)); // 10 font size + 5 top + 5 bottom
      expect(occ.getWidth(), greaterThan(40)); // Text width (~35) + 20
      expect(
          occ.getHeight(), closeTo(20, 0.1)); // 10 font size + 5 top + 5 bottom
    });

    test('MinMaxWidth calculation', () async {
      final ttf = TrueTypeFont.fromFile("c:/windows/fonts/arial.ttf");
      final font = PdfTrueTypeFont(ttf);

      final textElement = Text("Hello World");
      textElement.setProperty(Property.FONT, font);
      textElement.setProperty(
          Property.FONT_SIZE, UnitValue.createPointValue(10));

      final renderer = TextRenderer(textElement);
      MinMaxWidth? mmw = renderer.getMinMaxWidth();
      expect(mmw, isNotNull);

      print("Min: ${mmw!.getMinWidth()}, Max: ${mmw.getMaxWidth()}");

      expect(mmw.getMinWidth(), greaterThan(20));
      expect(mmw.getMaxWidth(), greaterThan(mmw.getMinWidth()));
    });
  });
}
