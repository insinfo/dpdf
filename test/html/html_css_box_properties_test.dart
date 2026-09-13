import 'package:html/parser.dart' as html_parser;

import 'package:dpdf/src/html/css/css_values.dart';
import 'package:dpdf/src/html/css/html_style_sheet.dart';
import 'package:dpdf/src/html/dom/html_box_builder.dart';
import 'package:dpdf/src/html/html_to_pdf.dart';
import 'package:dpdf/src/html/layout/html_layout_engine.dart';
import 'package:dpdf/src/html/model/html_box.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:test/test.dart';

/// Builds the normalized box tree of an HTML fragment.
List<HtmlBox> _boxes(String html) {
  final document = html_parser.parse(html);
  final sheet = HtmlStyleSheet.fromDocument(document);
  return HtmlBoxBuilder(sheet, 12).build(document.body!.nodes);
}

/// The style of the first text box holding exactly [text].
HtmlTextStyle _textStyle(List<HtmlBox> boxes, String text) {
  final found = _find(boxes, text);
  if (found == null) throw StateError('no text box holding "$text"');
  return found.style.text;
}

HtmlBox? _find(List<HtmlBox> boxes, String text) {
  for (final box in boxes) {
    if (box.text?.trim() == text) return box;
    final found = _find(box.children, text);
    if (found != null) return found;
  }
  return null;
}

HtmlBox _block(List<HtmlBox> children,
        {CssLength height = const CssLength.auto(), double fontSize = 12}) =>
    HtmlBox(
      style: HtmlBoxStyle(
        display: HtmlDisplay.block,
        text: HtmlTextStyle(fontSize),
        height: height,
      ),
      children: children,
    );

HtmlBox _inline(String text,
        {double? lineHeightFactor, double fontSize = 12}) =>
    HtmlBox(
      style: HtmlBoxStyle(
        display: HtmlDisplay.inline,
        text: HtmlTextStyle(fontSize, lineHeightFactor: lineHeightFactor),
      ),
      text: text,
    );

Future<String> _render(String html) async {
  final bytes = await HtmlConverter.convertToBytes(html);
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  try {
    final page = (await document.pageAt(1))!;
    return String.fromCharCodes(await page.contentPayload());
  } finally {
    await document.close();
  }
}

void main() {
  group('CSS line-height', () {
    test('a number multiplies the font size of the box', () {
      final style = _textStyle(
          _boxes('<p style="font-size:20px;line-height:2">text</p>'), 'text');

      expect(style.lineHeightFactor, 2);
      expect(style.lineHeight, closeTo(style.fontSize * 2, 1e-9));
    });

    test('a number inherits as the factor, not as the length it produced', () {
      final style = _textStyle(
          _boxes('<div style="font-size:10px;line-height:2">'
              '<span style="font-size:20px">child</span></div>'),
          'child');

      expect(style.lineHeightFactor, 2);
      expect(style.fontSize, closeTo(15, 1e-9));
      expect(style.lineHeight, closeTo(30, 1e-9),
          reason: 'the child scales the inherited factor by its own size');
    });

    test('a length inherits already computed', () {
      final style = _textStyle(
          _boxes('<div style="font-size:10px;line-height:30px">'
              '<span style="font-size:20px">child</span></div>'),
          'child');

      expect(style.lineHeightLength, closeTo(22.5, 1e-9));
      expect(style.lineHeight, closeTo(22.5, 1e-9));
    });

    test('a percentage is computed against the declaring font size', () {
      final style = _textStyle(
          _boxes('<p style="font-size:20px;line-height:150%">t</p>'), 't');

      expect(style.lineHeight, closeTo(20 * .75 * 1.5, 1e-9));
    });

    test('normal drops an inherited value back to the engine ratio', () {
      final style = _textStyle(
          _boxes('<div style="line-height:3">'
              '<p style="line-height:normal">child</p></div>'),
          'child');

      expect(style.lineHeightFactor, isNull);
      expect(style.lineHeight, closeTo(style.fontSize * 1.35, 1e-9));
    });

    test('the layout engine spaces wrapped lines by the resolved height', () {
      const prose = 'one two three four five six seven eight nine ten';
      final tight = HtmlLayoutEngine(60).layout([
        _block([_inline(prose, lineHeightFactor: 1)])
      ]);
      final loose = HtmlLayoutEngine(60).layout([
        _block([_inline(prose, lineHeightFactor: 3)])
      ]);

      expect(tight.length, greaterThan(1));
      expect(loose.length, tight.length);
      expect(loose[1].baseline - loose[0].baseline,
          closeTo((tight[1].baseline - tight[0].baseline) * 3, 1e-9));
    });
  });

  group('CSS height', () {
    test('a declared height reaches the box style in points', () {
      expect(
          _boxes('<div style="height:120px">content</div>')
              .first
              .style
              .height
              .points,
          closeTo(90, 1e-9));
    });

    test('an explicit height pushes the following box down', () {
      List<HtmlBox> tree(CssLength height) => [
            _block([_inline('short')], height: height),
            _block([_inline('after')]),
          ];

      final plain =
          HtmlLayoutEngine(300).layout(tree(const CssLength.auto())).last;
      final tall =
          HtmlLayoutEngine(300).layout(tree(const CssLength.points(200))).last;

      expect(tall.baseline - plain.baseline, greaterThan(150));
    });

    test('a percentage height stays auto without a sized containing block', () {
      List<HtmlBox> tree(CssLength height) => [
            _block([_inline('short')], height: height),
            _block([_inline('after')]),
          ];

      final plain =
          HtmlLayoutEngine(300).layout(tree(const CssLength.auto())).last;
      final percent =
          HtmlLayoutEngine(300).layout(tree(const CssLength.percent(0.5))).last;

      expect(percent.baseline, closeTo(plain.baseline, 1e-9));
    });

    test('content taller than the declared height is never dropped', () {
      const prose = 'one two three four five six seven eight nine ten eleven';
      final fragments = HtmlLayoutEngine(60).layout([
        _block([_inline(prose)], height: const CssLength.points(4))
      ]);

      expect(fragments.length, greaterThan(3));
    });
  });

  group('CSS text-decoration', () {
    test('underline reaches the text style', () {
      expect(
          _textStyle(_boxes('<p style="text-decoration:underline">t</p>'), 't')
              .decoration,
          {HtmlTextDecoration.underline});
    });

    test('the u and del tags carry their presentational decoration', () {
      expect(_textStyle(_boxes('<u>a</u>'), 'a').decoration,
          {HtmlTextDecoration.underline});
      expect(_textStyle(_boxes('<del>a</del>'), 'a').decoration,
          {HtmlTextDecoration.lineThrough});
    });

    test('the decoration reaches the text of a descendant box', () {
      expect(
          _textStyle(
                  _boxes('<div style="text-decoration:line-through">'
                      '<span>child</span></div>'),
                  'child')
              .decoration,
          {HtmlTextDecoration.lineThrough});
    });

    test('none stops a decoration coming from an ancestor', () {
      expect(
          _textStyle(
                  _boxes('<div style="text-decoration:underline">'
                      '<span style="text-decoration:none">child</span></div>'),
                  'child')
              .decoration,
          isEmpty);
    });

    test('the painter draws a rule only for decorated text', () async {
      final decorated =
          await _render('<p style="text-decoration:underline">word</p>');
      final plain = await _render('<p>word</p>');

      expect(decorated, contains(' re\n'));
      expect(plain, isNot(contains(' re\n')));
    });

    test('overline and line-through each produce their own rule', () async {
      final content = await _render(
          '<p style="text-decoration:overline line-through">word</p>');

      expect(RegExp(r' re\n').allMatches(content).length, 2);
    });
  });
}
