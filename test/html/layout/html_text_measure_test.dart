import 'package:dpdf/src/html/layout/html_text_measure.dart';
import 'package:dpdf/src/html/model/html_box.dart';
import 'package:test/test.dart';

const _helvetica = CraftHtmlTextStyle(10);
const _bold = CraftHtmlTextStyle(10, bold: true);
const _courier = CraftHtmlTextStyle(10, fontFamily: 'monospace');
const _times = CraftHtmlTextStyle(10, fontFamily: 'serif');

void main() {
  group('CraftHtmlTextMeasure', () {
    test('gives narrow and wide glyphs different widths', () {
      // The old average-width estimate made these equal, which is what broke
      // line breaking and centring for real text.
      final narrow = CraftHtmlTextMeasure.text('iiiii', _helvetica);
      final wide = CraftHtmlTextMeasure.text('WWWWW', _helvetica);

      expect(narrow, lessThan(wide));
      expect(wide / narrow, greaterThan(3));
    });

    test('measures a monospaced face as uniform', () {
      final narrow = CraftHtmlTextMeasure.text('iiiii', _courier);
      final wide = CraftHtmlTextMeasure.text('WWWWW', _courier);

      expect(narrow, closeTo(wide, 1e-9));
      // Courier advances 600/1000 em per glyph.
      expect(narrow, closeTo(5 * 0.6 * 10, 1e-9));
    });

    test('scales linearly with the font size', () {
      final small = CraftHtmlTextMeasure.text('Hello', _helvetica);
      final large =
          CraftHtmlTextMeasure.text('Hello', const CraftHtmlTextStyle(20));

      expect(large, closeTo(small * 2, 1e-9));
    });

    test('distinguishes the faces a CSS style resolves to', () {
      final regular = CraftHtmlTextMeasure.text('Handgloves', _helvetica);
      final bold = CraftHtmlTextMeasure.text('Handgloves', _bold);
      final serif = CraftHtmlTextMeasure.text('Handgloves', _times);

      expect(bold, greaterThan(regular));
      expect(serif, isNot(closeTo(regular, 0.01)));
    });

    test('measures an empty string as nothing', () {
      expect(CraftHtmlTextMeasure.text('', _helvetica), isZero);
    });

    test('reports the width of a space', () {
      // Helvetica's space advances 278/1000 em.
      expect(CraftHtmlTextMeasure.space(_helvetica), closeTo(2.78, 1e-9));
      expect(CraftHtmlTextMeasure.space(_courier), closeTo(6.0, 1e-9));
    });

    test('budgets more monospaced characters for a wider line', () {
      final narrowLine = CraftHtmlTextMeasure.charactersPerLine(_courier, 60);
      final wideLine = CraftHtmlTextMeasure.charactersPerLine(_courier, 600);

      expect(narrowLine, equals(10));
      expect(wideLine, equals(100));
    });

    test('never budgets fewer than one character', () {
      expect(
          CraftHtmlTextMeasure.charactersPerLine(_helvetica, 0.1), equals(1));
    });

    test('measures characters outside the face without failing', () {
      // A codepoint WinAnsi cannot encode falls back to a space advance
      // instead of aborting the page.
      final width = CraftHtmlTextMeasure.text('中文', _helvetica);

      expect(width, greaterThan(0));
      expect(width.isFinite, isTrue);
    });
  });
}
