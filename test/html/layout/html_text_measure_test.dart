import 'package:dpdf/src/html/layout/html_text_measure.dart';
import 'package:dpdf/src/html/model/html_box.dart';
import 'package:test/test.dart';

const _helvetica = HtmlTextStyle(10);
const _bold = HtmlTextStyle(10, bold: true);
const _courier = HtmlTextStyle(10, fontFamily: 'monospace');
const _times = HtmlTextStyle(10, fontFamily: 'serif');

void main() {
  group('HtmlTextMeasure', () {
    test('gives narrow and wide glyphs different widths', () {
      // The old average-width estimate made these equal, which is what broke
      // line breaking and centring for real text.
      final narrow = HtmlTextMeasure.text('iiiii', _helvetica);
      final wide = HtmlTextMeasure.text('WWWWW', _helvetica);

      expect(narrow, lessThan(wide));
      expect(wide / narrow, greaterThan(3));
    });

    test('measures a monospaced face as uniform', () {
      final narrow = HtmlTextMeasure.text('iiiii', _courier);
      final wide = HtmlTextMeasure.text('WWWWW', _courier);

      expect(narrow, closeTo(wide, 1e-9));
      // Courier advances 600/1000 em per glyph.
      expect(narrow, closeTo(5 * 0.6 * 10, 1e-9));
    });

    test('scales linearly with the font size', () {
      final small = HtmlTextMeasure.text('Hello', _helvetica);
      final large = HtmlTextMeasure.text('Hello', const HtmlTextStyle(20));

      expect(large, closeTo(small * 2, 1e-9));
    });

    test('distinguishes the faces a CSS style resolves to', () {
      final regular = HtmlTextMeasure.text('Handgloves', _helvetica);
      final bold = HtmlTextMeasure.text('Handgloves', _bold);
      final serif = HtmlTextMeasure.text('Handgloves', _times);

      expect(bold, greaterThan(regular));
      expect(serif, isNot(closeTo(regular, 0.01)));
    });

    test('measures an empty string as nothing', () {
      expect(HtmlTextMeasure.text('', _helvetica), isZero);
    });

    test('reports the width of a space', () {
      // Helvetica's space advances 278/1000 em.
      expect(HtmlTextMeasure.space(_helvetica), closeTo(2.78, 1e-9));
      expect(HtmlTextMeasure.space(_courier), closeTo(6.0, 1e-9));
    });

    test('budgets more monospaced characters for a wider line', () {
      final narrowLine = HtmlTextMeasure.charactersPerLine(_courier, 60);
      final wideLine = HtmlTextMeasure.charactersPerLine(_courier, 600);

      expect(narrowLine, equals(10));
      expect(wideLine, equals(100));
    });

    test('never budgets fewer than one character', () {
      expect(HtmlTextMeasure.charactersPerLine(_helvetica, 0.1), equals(1));
    });

    test('measures characters outside the face without failing', () {
      // A codepoint WinAnsi cannot encode falls back to a space advance
      // instead of aborting the page.
      final width = HtmlTextMeasure.text('中文', _helvetica);

      expect(width, greaterThan(0));
      expect(width.isFinite, isTrue);
    });
  });
}
