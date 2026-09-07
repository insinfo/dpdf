import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';
import 'package:dpdf/src/render/page_renderer.dart';
import 'package:test/test.dart';

const _fontPath = 'test/assets/ABeeZee-Regular.ttf';

/// Builds a one-page PDF whose text is drawn with an embedded TrueType font.
Future<Uint8List> _pageWithText(
  String text, {
  double size = 36,
  double x = 20,
  double y = 40,
  double width = 320,
  double height = 100,
  int renderMode = 0,
  double charSpacing = 0,
  double horizontalScale = 100,
}) async {
  final output = BytesBuilder(copy: false);
  final pdf = CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(output));
  final page = await pdf.appendBlankPage();
  page.pdfRepresentation().put(
      CraftPdfName.mediaBox, CraftPdfArray.fromDoubles([0, 0, width, height]));

  final program = CraftTrueTypeFont.fromFile(_fontPath);
  // The third argument embeds the program, which is what gives the renderer
  // outlines to draw.
  final font = CraftPdfTrueTypeFont(program, 'WinAnsiEncoding', true);

  final canvas = await CraftPdfCanvas.fromPage(page);
  canvas.beginText();
  await canvas.setFontAndSize(font, size);
  if (renderMode != 0) canvas.setTextRenderingMode(renderMode);
  if (charSpacing != 0) canvas.setCharacterSpacing(charSpacing);
  if (horizontalScale != 100) canvas.setHorizontalScaling(horizontalScale);
  canvas.moveText(x, y);
  canvas.showText(text);
  canvas.endText();

  await pdf.close();
  return output.takeBytes();
}

Future<PdfRenderedPage> _render(Uint8List bytes, {double dpi = 72}) async {
  final document = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
  try {
    return await PdfPageRenderer.render((await document.pageAt(1))!,
        options: PdfRenderOptions(dpi: dpi));
  } finally {
    await document.close();
  }
}

/// How many pixels are darker than mid grey — i.e. how much ink was laid down.
int _inked(PdfRenderedPage page) {
  var count = 0;
  for (final pixel in page.pixels) {
    if ((pixel & 0xFF) < 128) count++;
  }
  return count;
}

/// The horizontal extent of the inked pixels, as (leftmost, rightmost).
(int, int)? _inkExtent(PdfRenderedPage page) {
  int? left, right;
  for (var y = 0; y < page.height; y++) {
    for (var x = 0; x < page.width; x++) {
      if ((page.pixels[y * page.width + x] & 0xFF) >= 128) continue;
      if (left == null || x < left) left = x;
      if (right == null || x > right) right = x;
    }
  }
  return left == null ? null : (left, right!);
}

void main() {
  // Without the font there is nothing to embed, and a test that silently
  // passes on a missing asset is worse than one that is absent.
  setUpAll(() {
    if (!File(_fontPath).existsSync()) {
      throw StateError('missing test asset $_fontPath');
    }
  });

  group('PdfPageRenderer glyphs', () {
    test('draws an embedded TrueType font instead of reporting it skipped',
        () async {
      final page = await _render(await _pageWithText('Hamburg'));

      expect(page.report.glyphsSkipped, isZero,
          reason: 'the font is embedded, so nothing should be skipped');
      expect(page.report.isComplete, isTrue);
      expect(_inked(page), greaterThan(200),
          reason: 'seven glyphs at 36pt have to put down real ink');
    });

    test('puts the ink where the text was positioned', () async {
      final page = await _render(await _pageWithText('Hi', x: 200));
      final extent = _inkExtent(page);

      expect(extent, isNotNull);
      // Text starts at x=200 in a 320-point page, so nothing may land left of
      // it. This is what catches a text matrix composed in the wrong order.
      expect(extent!.$1, greaterThanOrEqualTo(195));
    });

    test('advances the text matrix, so a longer string is wider', () async {
      final short = _inkExtent(await _render(await _pageWithText('I')))!;
      final long = _inkExtent(await _render(await _pageWithText('IIIIIIII')))!;

      final shortWidth = short.$2 - short.$1;
      final longWidth = long.$2 - long.$1;
      expect(longWidth, greaterThan(shortWidth * 4),
          reason: 'eight glyphs must be far wider than one; if the advance '
              'were dropped they would all stack on the same spot');
    });

    test('honours Tc by spreading the same string wider', () async {
      final normal = _inkExtent(await _render(await _pageWithText('IIII')))!;
      final spaced = _inkExtent(
          await _render(await _pageWithText('IIII', charSpacing: 8)))!;

      expect(spaced.$2 - spaced.$1, greaterThan(normal.$2 - normal.$1),
          reason: 'Tc adds to every advance, so the run must get wider');
    });

    test('honours Tz, which scales advances and glyphs together', () async {
      final normal = _inkExtent(await _render(await _pageWithText('IIII')))!;
      final wide = _inkExtent(
          await _render(await _pageWithText('IIII', horizontalScale: 200)))!;

      // At 200% both the outline and the advance double, so the run is about
      // twice as wide. Testing only the advance would miss a glyph transform
      // that forgot the horizontal scale.
      final normalWidth = normal.$2 - normal.$1;
      final wideWidth = wide.$2 - wide.$1;
      expect(wideWidth, greaterThan(normalWidth * 1.7));
      expect(wideWidth, lessThan(normalWidth * 2.3));
    });

    test('draws nothing in text rendering mode 3, which is invisible',
        () async {
      final visible = await _render(await _pageWithText('Hamburg'));
      final hidden =
          await _render(await _pageWithText('Hamburg', renderMode: 3));

      expect(_inked(visible), greaterThan(200));
      expect(_inked(hidden), isZero,
          reason: 'mode 3 is what keeps the OCR layer of a scan hidden');
    });

    test('scales with the render dpi', () async {
      final at72 = await _render(await _pageWithText('Hamburg'));
      final at144 = await _render(await _pageWithText('Hamburg'), dpi: 144);

      // Four times the pixels means roughly four times the ink; anti-aliasing
      // and stem rounding keep it from being exact.
      expect(_inked(at144), greaterThan(_inked(at72) * 3));
    });

    test('reports text as skipped when the font is not embedded', () async {
      // A base-14 font carries no program. Substituting a different typeface
      // would change the page, so the renderer says so instead.
      final output = BytesBuilder(copy: false);
      final pdf =
          CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(output));
      final page = await pdf.appendBlankPage();
      final canvas = await CraftPdfCanvas.fromPage(page);
      canvas.beginText();
      await canvas.setFontAndSize(pdf.defaultTypeface()!, 24);
      canvas.moveText(20, 100);
      canvas.showText('Helvetica');
      canvas.endText();
      await pdf.close();

      final rendered = await _render(output.takeBytes());
      expect(rendered.report.glyphsSkipped, greaterThan(0));
      expect(rendered.report.isComplete, isFalse);
    });
  });
}
