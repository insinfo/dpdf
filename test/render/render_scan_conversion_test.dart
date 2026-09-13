import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// Renders [content] on a 100 by 100 point page.
Future<PdfRenderedPage> _render(String content, {double dpi = 72}) async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  page.pdfRepresentation()
    ..put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, 100, 100]))
    ..put(PdfName.contents,
        PdfStream.withBytes(Uint8List.fromList(latin1.encode(content)), 0));
  await document.close();

  final reopened =
      await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
  try {
    return await PdfPageRenderer.render(
      (await reopened.pageAt(1))!,
      options: PdfRenderOptions(dpi: dpi),
    );
  } finally {
    await reopened.close();
  }
}

/// The red channel of every pixel in column [x], top to bottom.
List<int> _column(PdfRenderedPage page, int x) => [
      for (var y = 0; y < page.height; y++)
        (page.pixels[y * page.width + x] >> 16) & 0xff,
    ];

/// How much ink column [x] holds, in whole pixels.
///
/// Black on white, so one fully covered pixel is one unit. Summing instead of
/// looking at a single row is what makes the measurement independent of where
/// the feature happens to land on the pixel grid.
double _ink(PdfRenderedPage page, int x) {
  var total = 0.0;
  for (final value in _column(page, x)) {
    total += (255 - value) / 255;
  }
  return total;
}

/// How much ink the whole page holds, in whole pixels.
double _inkTotal(PdfRenderedPage page) {
  var total = 0.0;
  for (final word in page.pixels) {
    total += (255 - ((word >> 16) & 0xff)) / 255;
  }
  return total;
}

void main() {
  group('scan conversion, clause 10.6', () {
    test('a zero width line is one device pixel, at any resolution', () async {
      // Clause 8.4.3.2: a line width of 0 denotes the thinnest line the
      // device can render, one pixel wide. It must not vanish, and it must
      // not grow with the resolution either.
      final at72 = await _render('0 G 0 w 10 50.5 m 90 50.5 l S');
      expect(_ink(at72, 50), closeTo(1.0, 0.02));

      final at300 = await _render('0 G 0 w 10 50.5 m 90 50.5 l S', dpi: 300);
      expect(_ink(at300, 200), closeTo(1.0, 0.02));
    });

    test('a negative line width is ignored', () async {
      // Clause 8.4.3.2 admits no negative width; the previous value stands.
      final page = await _render('0 G -3 w 10 50.5 m 90 50.5 l S');
      expect(_ink(page, 50), closeTo(1.0, 0.02));
    });

    test('a line thinner than a pixel keeps its weight rather than vanishing',
        () async {
      // This renderer resolves coverage rather than following the pixel
      // centre rule of clause 10.6.1 literally: a half point line at 72 dpi
      // covers half a pixel and is painted at half intensity. Under the
      // pixel centre rule it would be all or nothing depending on where it
      // fell, which is what makes hairline rules flicker in and out of a
      // table when the page is scaled.
      final half = await _render('0 G 0.5 w 10 50.5 m 90 50.5 l S');
      expect(_ink(half, 50), closeTo(0.5, 0.02));

      final quarter = await _render('0 G 0.25 w 10 50.5 m 90 50.5 l S');
      expect(_ink(quarter, 50), closeTo(0.25, 0.02));
    });

    test('a filled sliver narrower than a pixel still paints', () async {
      // The same rule applied to filling: a quarter point tall rectangle is
      // a quarter of a pixel of ink.
      final page = await _render('0 g 10 50.25 80 0.25 re f');
      expect(_ink(page, 50), closeTo(0.25, 0.02));
    });

    test('a degenerate subpath paints a dot under round caps', () async {
      // Clause 8.5.3.2: a subpath that never leaves its starting point is
      // painted by `S` only with round caps, as a filled circle of the line
      // width. This is how a producer draws a dot.
      final page = await _render('0 G 1 J 4 w 50 50 m 50 50 l S');

      final column = _column(page, 50);
      expect(column[49], equals(0));
      expect(column[50], equals(0));
      // A circle of diameter four covers four rows and no more.
      expect(column[46], equals(255));
      expect(column[54], equals(255));
      // The mark is exactly the circle the renderer would draw from curves.
      // Comparing the two rather than to pi r squared keeps the check on the
      // shape: the rasterizer's coverage of a curved edge is a little under
      // the true area, and the dot should share that, not correct for it.
      final drawn = await _render('0 g 48 50 m 48 51.104 48.896 52 50 52 c '
          '51.104 52 52 51.104 52 50 c 52 48.896 51.104 48 50 48 c '
          '48.896 48 48 48.896 48 50 c f');
      expect(_inkTotal(page), closeTo(_inkTotal(drawn), 0.1));
    });

    test('a closed single point subpath paints the same dot', () async {
      final page = await _render('0 G 1 J 4 w 50 50 m h S');
      expect(_column(page, 50)[50], equals(0));
    });

    test('a degenerate subpath paints nothing under butt or square caps',
        () async {
      // The cap has no direction to be built on, so the spec asks for no
      // output at all rather than for a guess.
      for (final cap in ['0', '2']) {
        final page = await _render('0 G $cap J 4 w 50 50 m 50 50 l S');
        expect(_ink(page, 50), closeTo(0, 0.001), reason: 'cap $cap');
      }
    });

    test('a zero width dot is one device pixel across', () async {
      // Diameter one device pixel, so the disc is under a pixel of ink but
      // clearly there — and identical to the dot a line width of one draws,
      // which is what "the thinnest line the device can render" means.
      final zero = await _render('0 G 1 J 0 w 50 50 m 50 50 l S');
      final one = await _render('0 G 1 J 1 w 50 50 m 50 50 l S');
      expect(_inkTotal(zero), greaterThan(0.3));
      expect(_inkTotal(zero), lessThan(1.2));
      expect(_inkTotal(zero), closeTo(_inkTotal(one), 0.001));
    });

    test('a real segment in the same path still strokes normally', () async {
      // The dot is painted beside the stroke, not instead of it.
      final page =
          await _render('0 G 1 J 4 w 20 20 m 20 20 l 10 80 m 90 80 l S');
      expect(_column(page, 20)[80], equals(0)); // the dot
      expect(_column(page, 50)[20], equals(0)); // the line
    });
  });
}
