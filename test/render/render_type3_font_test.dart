import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// A one-page document whose content stream is [content].
Future<PdfDocument> _document(
  String content, {
  double width = 100,
  double height = 100,
  PdfDictionary? resources,
}) async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  page.pdfRepresentation()
    ..put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, width, height]))
    ..put(PdfName.contents,
        PdfStream.withBytes(Uint8List.fromList(latin1.encode(content)), 0));
  if (resources != null) {
    page.pdfRepresentation().put(PdfName.resources, resources);
  }
  await document.close();

  return PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
}

Future<PdfRenderedPage> _render(
  String content, {
  double width = 100,
  double height = 100,
  PdfDictionary? resources,
}) async {
  final document = await _document(content,
      width: width, height: height, resources: resources);
  try {
    return await PdfPageRenderer.render(
      (await document.pageAt(1))!,
      options: const PdfRenderOptions(dpi: 72),
    );
  } finally {
    await document.close();
  }
}

({int a, int r, int g, int b}) _at(PdfRenderedPage page, int x, int y) {
  final word = page.pixels[y * page.width + x];
  return (
    a: (word >> 24) & 0xff,
    r: (word >> 16) & 0xff,
    g: (word >> 8) & 0xff,
    b: word & 0xff,
  );
}

void _expectRgb(({int a, int r, int g, int b}) pixel, List<int> expected,
    {int tolerance = 1}) {
  expect(pixel.r, closeTo(expected[0], tolerance), reason: 'red');
  expect(pixel.g, closeTo(expected[1], tolerance), reason: 'green');
  expect(pixel.b, closeTo(expected[2], tolerance), reason: 'blue');
}

PdfStream _charProc(String content) =>
    PdfStream.withBytes(Uint8List.fromList(latin1.encode(content)), 0);

/// Wraps a Type 3 font in a `/Resources` dictionary under the name `F1`.
///
/// [procedures] maps a glyph name to its procedure; [differences] maps a
/// character code to one of those names.
PdfDictionary _type3Resources({
  required Map<String, String> procedures,
  required Map<int, String> differences,
  List<double> fontMatrix = const [0.001, 0, 0, 0.001, 0, 0],
  List<double> widths = const [1000],
  int firstChar = 97,
  bool includeCharProcs = true,
  PdfDictionary? fontResources,
}) {
  final charProcs = PdfDictionary();
  procedures.forEach(
      (name, content) => charProcs.put(PdfName(name), _charProc(content)));

  final differencesArray = PdfArray();
  final codes = differences.keys.toList()..sort();
  for (final code in codes) {
    differencesArray.add(PdfNumber.fromInt(code));
    differencesArray.add(PdfName(differences[code]!));
  }

  final font = PdfDictionary()
    ..put(PdfName.type, PdfName('Font'))
    ..put(PdfName.subtype, PdfName('Type3'))
    ..put(PdfName('FontBBox'), PdfArray.fromDoubles([0, 0, 1000, 1000]))
    ..put(PdfName('FontMatrix'), PdfArray.fromDoubles(fontMatrix))
    ..put(PdfName('Encoding'),
        PdfDictionary()..put(PdfName('Differences'), differencesArray))
    ..put(PdfName('FirstChar'), PdfNumber.fromInt(firstChar))
    ..put(PdfName('LastChar'), PdfNumber.fromInt(firstChar + widths.length - 1))
    ..put(PdfName('Widths'), PdfArray.fromDoubles(widths));
  if (includeCharProcs) font.put(PdfName('CharProcs'), charProcs);
  if (fontResources != null) font.put(PdfName.resources, fontResources);

  return PdfDictionary()
    ..put(PdfName('Font'), PdfDictionary()..put(PdfName('F1'), font));
}

/// A procedure that fills the whole 1000x1000 glyph square, declared with
/// `d0` so its own colour operators count.
const _colouredSquare = '1000 0 d0 1 0 0 rg 0 0 1000 1000 re f';

/// The same square declared with `d1`, which makes it a shape only.
const _shapeSquare = '1000 0 0 0 1000 1000 d1 1 0 0 rg 0 0 1000 1000 re f';

void main() {
  group('Type 3 fonts, clause 9.6.5', () {
    test('draws a glyph by running its CharProcs stream', () async {
      // A 10 point glyph at (10, 10): the font matrix takes the 1000 unit
      // square down to one text unit, and the font size scales it to ten.
      final page = await _render(
        'BT /F1 10 Tf 10 10 Td (a) Tj ET',
        resources: _type3Resources(
          procedures: {'square': '1000 0 d0 0 g 0 0 1000 1000 re f'},
          differences: {97: 'square'},
        ),
      );

      expect(page.report.glyphsSkipped, equals(0));
      expect(page.report.isComplete, isTrue, reason: page.report.toString());
      // The glyph covers user space (10, 10) to (20, 20), which on a 100
      // point page is image rows 80 to 90.
      _expectRgb(_at(page, 15, 85), [0, 0, 0]);
      _expectRgb(_at(page, 50, 50), [255, 255, 255]);
    });

    test('the font matrix scales the glyph', () async {
      // Half the usual glyph space makes the same 1000 unit square draw at
      // half the size: five points instead of ten.
      final page = await _render(
        'BT /F1 10 Tf 10 10 Td (a) Tj ET',
        resources: _type3Resources(
          procedures: {'square': '1000 0 d0 0 g 0 0 1000 1000 re f'},
          differences: {97: 'square'},
          fontMatrix: const [0.0005, 0, 0, 0.0005, 0, 0],
        ),
      );

      // Inside the five point square.
      _expectRgb(_at(page, 12, 88), [0, 0, 0]);
      // Where the full size glyph would have reached, but this one does not.
      _expectRgb(_at(page, 18, 82), [255, 255, 255]);
    });

    test('advances by /Widths mapped through the font matrix', () async {
      // Two glyphs in a row. With a width of 1000 glyph units and a size of
      // ten, each advances ten points, so the second sits at x = 20.
      final page = await _render(
        'BT /F1 10 Tf 10 10 Td (aa) Tj ET',
        resources: _type3Resources(
          procedures: {'square': '1000 0 d0 0 g 0 0 1000 1000 re f'},
          differences: {97: 'square'},
        ),
      );

      _expectRgb(_at(page, 15, 85), [0, 0, 0]);
      _expectRgb(_at(page, 25, 85), [0, 0, 0]);
      _expectRgb(_at(page, 35, 85), [255, 255, 255]);
    });

    test('a halved font matrix halves the advance too', () async {
      // The width is in glyph space, so the same 1000 goes through the same
      // matrix: five points per glyph rather than ten.
      final page = await _render(
        'BT /F1 10 Tf 10 10 Td (aa) Tj ET',
        resources: _type3Resources(
          procedures: {'square': '1000 0 d0 0 g 0 0 1000 1000 re f'},
          differences: {97: 'square'},
          fontMatrix: const [0.0005, 0, 0, 0.0005, 0, 0],
        ),
      );

      // Two five point squares end to end cover x = 10 to 20 with no gap.
      _expectRgb(_at(page, 12, 88), [0, 0, 0]);
      _expectRgb(_at(page, 17, 88), [0, 0, 0]);
      _expectRgb(_at(page, 22, 88), [255, 255, 255]);
    });

    test('a d0 glyph keeps the colour its procedure sets', () async {
      final page = await _render(
        'BT 0 1 0 rg /F1 10 Tf 10 10 Td (a) Tj ET',
        resources: _type3Resources(
          procedures: {'square': _colouredSquare},
          differences: {97: 'square'},
        ),
      );

      _expectRgb(_at(page, 15, 85), [255, 0, 0]);
    });

    test('a d1 glyph ignores its own colour operators', () async {
      // Clause 9.6.5: after `d1` the description is a shape, painted with the
      // colour in force where the text was shown. The red inside the
      // procedure is ignored and the green of the page wins.
      final page = await _render(
        'BT 0 1 0 rg /F1 10 Tf 10 10 Td (a) Tj ET',
        resources: _type3Resources(
          procedures: {'square': _shapeSquare},
          differences: {97: 'square'},
        ),
      );

      _expectRgb(_at(page, 15, 85), [0, 255, 0]);
    });

    test('the shape-only rule ends with the glyph', () async {
      // The `d1` of the first glyph must not silence the colour operators of
      // the page that follows it.
      final page = await _render(
        'BT 0 1 0 rg /F1 10 Tf 10 10 Td (a) Tj ET 1 0 0 rg 50 50 20 20 re f',
        resources: _type3Resources(
          procedures: {'square': _shapeSquare},
          differences: {97: 'square'},
        ),
      );

      _expectRgb(_at(page, 15, 85), [0, 255, 0]);
      _expectRgb(_at(page, 60, 40), [255, 0, 0]);
    });

    test('glyph procedures resolve XObjects against the font resources',
        () async {
      final form = PdfStream.withBytes(
          Uint8List.fromList(latin1.encode('0 g 0 0 1000 1000 re f')), 0)
        ..put(PdfName.subtype, PdfName('Form'))
        ..put(PdfName('BBox'), PdfArray.fromDoubles([0, 0, 1000, 1000]));
      final fontResources = PdfDictionary()
        ..put(PdfName('XObject'), PdfDictionary()..put(PdfName('Fx'), form));

      final page = await _render(
        'BT /F1 10 Tf 10 10 Td (a) Tj ET',
        resources: _type3Resources(
          procedures: {'square': '1000 0 d0 /Fx Do'},
          differences: {97: 'square'},
          fontResources: fontResources,
        ),
      );

      expect(page.report.glyphsSkipped, equals(0));
      _expectRgb(_at(page, 15, 85), [0, 0, 0]);
    });

    test('a code with no procedure is reported, not drawn', () async {
      final page = await _render(
        'BT /F1 10 Tf 10 10 Td (ab) Tj ET',
        resources: _type3Resources(
          procedures: {'square': '1000 0 d0 0 g 0 0 1000 1000 re f'},
          differences: {97: 'square'},
          widths: const [1000, 1000],
        ),
      );

      // The first code drew, the second had nothing to draw.
      expect(page.report.glyphsSkipped, equals(1));
      _expectRgb(_at(page, 15, 85), [0, 0, 0]);
      _expectRgb(_at(page, 25, 85), [255, 255, 255]);
    });

    test('a font without /CharProcs still reports the text as skipped',
        () async {
      final page = await _render(
        'BT /F1 10 Tf 10 10 Td (a) Tj ET',
        resources: _type3Resources(
          procedures: const {},
          differences: {97: 'square'},
          includeCharProcs: false,
        ),
      );

      expect(page.report.glyphsSkipped, greaterThan(0));
      expect(
          page.report.fontFailures['F1'], equals(PdfGlyphFailure.notEmbedded));
      // Uma Type 3 não tem substituta: seus códigos designam procedimentos com
      // nomes próprios, não caracteres. Emprestar os contornos de uma fonte de
      // texto desenharia letras no lugar dos desenhos do documento.
      expect(page.report.fontsSubstituted, isEmpty);
    });

    test('the text matrix survives a glyph procedure that shows text',
        () async {
      // A procedure that opens its own text object must not move the line the
      // outer text object is laying out.
      final page = await _render(
        'BT /F1 10 Tf 10 10 Td (aa) Tj ET',
        resources: _type3Resources(
          procedures: {
            'square': '1000 0 d0 BT 200 0 Td ET 0 g 0 0 1000 1000 re f',
          },
          differences: {97: 'square'},
        ),
      );

      _expectRgb(_at(page, 15, 85), [0, 0, 0]);
      _expectRgb(_at(page, 25, 85), [0, 0, 0]);
      _expectRgb(_at(page, 35, 85), [255, 255, 255]);
    });

    test('render mode 3 hides a Type 3 glyph but still advances', () async {
      final page = await _render(
        'BT /F1 10 Tf 3 Tr 10 10 Td (a) Tj 0 Tr (a) Tj ET',
        resources: _type3Resources(
          procedures: {'square': '1000 0 d0 0 g 0 0 1000 1000 re f'},
          differences: {97: 'square'},
        ),
      );

      // The invisible glyph left its cell blank, the visible one after it
      // landed one advance further along.
      _expectRgb(_at(page, 15, 85), [255, 255, 255]);
      _expectRgb(_at(page, 25, 85), [0, 0, 0]);
    });
  });
}
