import 'dart:io';

import 'package:dgfx/dgfx.dart';

import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/svg/svg_converter.dart';
import 'package:test/test.dart';

/// Converts [svg] to a one page PDF and returns the page content stream.
///
/// Text needs a font in the resource dictionary, which only exists inside a
/// document, so the loose canvas used by the other SVG tests is not enough.
Future<String> _render(String svg, {BLFontCollection? fonts}) async {
  final bytes = await SvgConverter.convertToBytes(svg, fontCollection: fonts);
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  try {
    final page = (await document.pageAt(1))!;
    return String.fromCharCodes(await page.contentPayload());
  } finally {
    await document.close();
  }
}

final RegExp _textMatrix = RegExp(
    r'(-?[\d.]+) (-?[\d.]+) (-?[\d.]+) (-?[\d.]+) (-?[\d.]+) (-?[\d.]+) Tm');

/// Every text matrix emitted by the content stream, in order.
List<List<double>> _matrices(String content) => [
      for (final match in _textMatrix.allMatches(content))
        [
          for (var group = 1; group <= 6; group++)
            double.parse(match.group(group)!)
        ]
    ];

List<String> _shownText(String content) => [
      for (final match in RegExp(r'\(([^)]*)\) Tj').allMatches(content))
        match.group(1)!
    ];

void main() {
  group('SVG text whitespace', () {
    test('collapses runs of whitespace and trims the element', () async {
      final content = await _render('''
        <svg width="200" height="30">
          <text x="10" y="20">
             Hello    World
          </text>
        </svg>
      ''');

      expect(_shownText(content), ['Hello World']);
    });

    test('merges whitespace across the boundary between two leaves', () async {
      final content = await _render('<svg width="200" height="30">'
          '<text x="10" y="20">a <tspan> b</tspan></text></svg>');

      expect(_shownText(content), ['a ', 'b']);
    });

    test('xml:space preserve keeps every space character', () async {
      final content = await _render('<svg width="200" height="30">'
          '<text x="10" y="20" xml:space="preserve">  A  B </text></svg>');

      expect(_shownText(content), ['  A  B ']);
    });
  });

  group('SVG text-anchor', () {
    test('middle and end shift the chunk by its own advance', () async {
      final content = await _render('''
        <svg width="300" height="60">
          <text x="100" y="10" text-anchor="start">AV</text>
          <text x="100" y="20" text-anchor="middle">AV</text>
          <text x="100" y="30" text-anchor="end">AV</text>
        </svg>
      ''');

      final matrices = _matrices(content);
      expect(matrices, hasLength(3));
      final start = matrices[0][4];
      final middle = matrices[1][4];
      final end = matrices[2][4];
      expect(start, closeTo(75, 1e-6),
          reason: 'start leaves the chunk on the declared point');
      // The content stream keeps two decimals above one, so the halves only
      // agree to within that rounding.
      expect(start - middle, closeTo((start - end) / 2, 0.01),
          reason: 'middle pulls the chunk back by half of what end does');
      expect(end, lessThan(middle));
    });

    test('an absolute x on a tspan anchors its own chunk', () async {
      final content = await _render('<svg width="300" height="30">'
          '<text x="20" y="20" text-anchor="end">A'
          '<tspan x="200">BB</tspan></text></svg>');

      final matrices = _matrices(content);
      expect(matrices, hasLength(2));
      expect(matrices[0][4], lessThan(15),
          reason: 'the first chunk ends at x=20px');
      expect(matrices[1][4], lessThan(150),
          reason: 'the tspan opens a second chunk anchored at x=200px');
      expect(matrices[1][4], greaterThan(100));
    });
  });

  group('SVG text positioning lists', () {
    test('a list of x values positions each character', () async {
      final content = await _render('<svg width="200" height="30">'
          '<text x="10 40" y="20">AB</text></svg>');

      final matrices = _matrices(content);
      expect(matrices, hasLength(2));
      expect(matrices[0][4], closeTo(7.5, 1e-6));
      expect(matrices[1][4], closeTo(30, 1e-6));
      expect(_shownText(content), ['A', 'B']);
    });

    test('a list of dy values shifts characters from the current position',
        () async {
      final content = await _render('<svg width="200" height="40">'
          '<text x="10" y="20" dy="0 8">AB</text></svg>');

      final matrices = _matrices(content);
      expect(matrices, hasLength(2));
      expect(matrices[0][5], closeTo(15, 1e-6));
      expect(matrices[1][5], closeTo(21, 1e-6),
          reason: '8px below the baseline is 6pt further down');
      expect(matrices[1][4], greaterThan(matrices[0][4]),
          reason: 'dy alone does not reset the horizontal advance');
    });

    test('rotate turns every glyph around its own origin', () async {
      final content = await _render('<svg width="200" height="40">'
          '<text x="10" y="20" rotate="90">AB</text></svg>');

      final matrices = _matrices(content);
      expect(matrices, hasLength(2));
      for (final matrix in matrices) {
        expect(matrix.sublist(0, 4), [0, 1, 1, 0],
            reason: 'a quarter turn clockwise in the SVG coordinate system');
      }
    });

    test('the last rotate value covers the remaining characters', () async {
      final content = await _render('<svg width="200" height="40">'
          '<text x="10" y="20" rotate="0 90">ABC</text></svg>');

      final matrices = _matrices(content);
      expect(matrices, hasLength(3));
      expect(matrices[0].sublist(0, 4), [1, 0, 0, -1]);
      expect(matrices[1].sublist(0, 4), [0, 1, 1, 0]);
      expect(matrices[2].sublist(0, 4), [0, 1, 1, 0]);
    });
  });

  group('SVG text spacing and decoration', () {
    test('letter-spacing becomes the character spacing operator', () async {
      final content = await _render('<svg width="200" height="30">'
          '<text x="10" y="20" letter-spacing="4">AB</text></svg>');

      expect(content, contains('3 Tc\n'),
          reason: '4px of letter spacing is 3pt');
      expect(_shownText(content), ['AB'],
          reason: 'spacing is a text state parameter, not a break');
    });

    test('letter-spacing widens the advance used by text-anchor', () async {
      final tight = await _render('<svg width="300" height="30">'
          '<text x="200" y="20" text-anchor="end">AB</text></svg>');
      final loose = await _render('<svg width="300" height="30">'
          '<text x="200" y="20" text-anchor="end" letter-spacing="10">'
          'AB</text></svg>');

      expect(_matrices(loose)[0][4], lessThan(_matrices(tight)[0][4]));
    });

    test('word-spacing repositions the word that follows a space', () async {
      final content = await _render('<svg width="300" height="30">'
          '<text x="10" y="20" word-spacing="20">A B</text></svg>');

      expect(_shownText(content), ['A ', 'B']);
      final matrices = _matrices(content);
      expect(matrices, hasLength(2));
      expect(matrices[1][4] - matrices[0][4], greaterThan(15),
          reason: '20px of word spacing is 15pt on top of the glyph advances');
    });

    test('text-decoration underline draws a bar after the glyphs', () async {
      final content = await _render('<svg width="200" height="30">'
          '<text x="10" y="20" text-decoration="underline">AB</text></svg>');

      final endOfText = content.indexOf('ET\n');
      final bar = content.indexOf(' re\n', endOfText);
      expect(endOfText, greaterThanOrEqualTo(0));
      expect(bar, greaterThan(endOfText));
      expect(content.substring(bar), contains('f\n'));
    });

    test('text-decoration none leaves no extra geometry', () async {
      final content = await _render('<svg width="200" height="30">'
          '<text x="10" y="20" text-decoration="none">AB</text></svg>');

      expect(content, isNot(contains(' re\nf\n')));
    });

    test('stroked text selects the fill and stroke rendering mode', () async {
      final content = await _render('<svg width="200" height="30">'
          '<text x="10" y="20" fill="blue" stroke="red">AB</text></svg>');

      expect(content, contains('2 Tr\n'));
    });

    test('unstroked text keeps the default rendering mode', () async {
      final content = await _render('<svg width="200" height="30">'
          '<text x="10" y="20">AB</text></svg>');

      expect(content, isNot(contains(' Tr\n')));
    });
  });

  group('SVG textPath', () {
    const track = '<defs><path id="track" d="M 10 40 L 190 40"/></defs>';

    test('places one glyph per character along the referenced path', () async {
      final content = await _render('<svg width="200" height="60">$track'
          '<text font-size="10"><textPath href="#track">AB</textPath>'
          '</text></svg>');

      final matrices = _matrices(content);
      expect(matrices, hasLength(2));
      expect(_shownText(content), ['A', 'B']);
      for (final matrix in matrices) {
        expect(matrix.sublist(0, 4), [1, 0, 0, -1],
            reason: 'a horizontal path leaves the glyphs upright');
        expect(matrix[5], closeTo(30, 1e-6),
            reason: 'the path sits at y=40px, that is 30pt');
      }
      expect(matrices[1][4], greaterThan(matrices[0][4]));
    });

    test('startOffset as a percentage moves the start along the path',
        () async {
      final plain = await _render('<svg width="200" height="60">$track'
          '<text font-size="10"><textPath href="#track">AB</textPath>'
          '</text></svg>');
      final offset = await _render('<svg width="200" height="60">$track'
          '<text font-size="10">'
          '<textPath href="#track" startOffset="50%">AB</textPath>'
          '</text></svg>');

      final start = _matrices(plain)[0][4];
      final moved = _matrices(offset)[0][4];
      // The path spans 180px, so half of it is 67.5pt further along.
      expect(moved - start, closeTo(67.5, 0.5));
    });

    test('glyphs pushed past the end of the path are dropped', () async {
      final content = await _render('<svg width="200" height="60">'
          '<defs><path id="stub" d="M 10 40 L 20 40"/></defs>'
          '<text font-size="20">'
          '<textPath href="#stub">ABCDEFGHIJ</textPath></text></svg>');

      expect(_shownText(content).length, lessThan(10));
    });

    test('a rotated path turns the glyphs with it', () async {
      final content = await _render('<svg width="200" height="200">'
          '<defs><path id="down" d="M 50 10 L 50 190"/></defs>'
          '<text font-size="10"><textPath href="#down">AB</textPath>'
          '</text></svg>');

      final matrices = _matrices(content);
      expect(matrices, hasLength(2));
      expect(matrices[0].sublist(0, 4), [0, 1, 1, 0],
          reason: 'the path runs downwards, so the glyphs turn a quarter '
              'clockwise');
    });

    test('an unresolvable textPath reference draws nothing', () async {
      final content = await _render('<svg width="200" height="60">'
          '<text font-size="10"><textPath href="#missing">AB</textPath>'
          '</text></svg>');

      expect(_shownText(content), isEmpty);
    });
  });

  group('SVG text fonts', () {
    test('a registered face is used for every positioned run', () async {
      final fontBytes =
          await File('test/assets/ABeeZee-Regular.ttf').readAsBytes();
      final fonts = BLFontCollection()
        ..addBytes(fontBytes, familyName: 'Example Sans');
      final content = await _render(
          '<svg width="200" height="30">'
          '<text font-family="Example Sans" x="10 40" y="20">AB</text></svg>',
          fonts: fonts);

      expect(_matrices(content), hasLength(2));
      expect(RegExp(r'<[0-9A-Fa-f]+> Tj').allMatches(content).length, 2,
          reason: 'the embedded face writes hexadecimal glyph codes');
    });
  });
}
