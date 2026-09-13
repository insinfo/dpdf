import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';
import 'package:test/test.dart';

const _fontPath = 'test/assets/ABeeZee-Regular.ttf';

/// A page that shows [text] in rendering mode [renderMode] and then paints a
/// red rectangle over the whole page.
///
/// Under a clipping mode the rectangle can only reach the glyph shapes, which
/// is what clause 9.3.6 asks for; under any other mode it covers everything.
Future<Uint8List> _page(
  String text, {
  required int renderMode,
  bool coverAfterwards = true,
  double lineWidth = 0,
  double width = 320,
  double height = 100,
}) async {
  final output = BytesBuilder(copy: false);
  final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await pdf.appendBlankPage();
  page
      .pdfRepresentation()
      .put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, width, height]));

  final font = PdfTrueTypeFont(
      TrueTypeFont.fromFile(_fontPath), 'WinAnsiEncoding', true);

  final canvas = await PdfCanvas.fromPage(page);
  canvas.saveState();
  canvas.beginText();
  await canvas.setFontAndSize(font, 48);
  canvas.setTextRenderingMode(renderMode);
  if (lineWidth > 0) canvas.setLineWidth(lineWidth);
  canvas.setFillColor(DeviceRgb(0, 0, 1));
  canvas.setStrokeColor(DeviceRgb(0, 1, 0));
  canvas.moveText(20, 30);
  canvas.showText(text);
  canvas.endText();
  if (coverAfterwards) {
    canvas.setFillColor(DeviceRgb(1, 0, 0));
    canvas.rectangle(0, 0, width, height);
    canvas.fill();
  }
  canvas.restoreState();

  await pdf.close();
  return output.takeBytes();
}

Future<PdfRenderedPage> _render(Uint8List bytes) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  try {
    return await PdfPageRenderer.render((await document.pageAt(1))!,
        options: const PdfRenderOptions(dpi: 72));
  } finally {
    await document.close();
  }
}

/// How many pixels carry [test]'s colour.
int _count(PdfRenderedPage page, bool Function(int r, int g, int b) test) {
  var count = 0;
  for (final pixel in page.pixels) {
    if (test((pixel >> 16) & 0xff, (pixel >> 8) & 0xff, pixel & 0xff)) {
      count++;
    }
  }
  return count;
}

bool _isRed(int r, int g, int b) => r > 200 && g < 60 && b < 60;
bool _isBlue(int r, int g, int b) => b > 200 && r < 60 && g < 60;
bool _isGreen(int r, int g, int b) => g > 200 && r < 60 && b < 60;
bool _isWhite(int r, int g, int b) => r > 240 && g > 240 && b > 240;

void main() {
  group('text rendering modes', () {
    test('mode 7 adds the glyphs to the clip without painting them', () async {
      final page = await _render(await _page('Hamburg', renderMode: 7));

      final red = _count(page, _isRed);
      final blue = _count(page, _isBlue);
      // The text itself is never painted, but the rectangle that follows is
      // confined to where the glyphs were.
      expect(blue, isZero, reason: 'mode 7 paints nothing itself');
      expect(red, greaterThan(200), reason: 'the cover reaches the glyphs');
      expect(red, lessThan(page.width * page.height ~/ 4),
          reason: 'the cover is confined to the glyphs');
      // A corner well away from the text stays as the page was.
      expect(_count(page, _isWhite), greaterThan(page.width * page.height ~/ 2));
    });

    test('mode 4 fills the glyphs and also clips', () async {
      final page = await _render(await _page('Hamburg', renderMode: 4));

      // The red cover lands on top of the blue text, so the glyphs end up red
      // and nothing outside them is touched.
      expect(_count(page, _isRed), greaterThan(200));
      expect(_count(page, _isWhite), greaterThan(page.width * page.height ~/ 2));
    });

    test('mode 0 does not clip anything', () async {
      final page = await _render(await _page('Hamburg', renderMode: 0));

      // Without a clipping mode the cover reaches the whole page.
      expect(_count(page, _isRed), equals(page.width * page.height));
    });

    test('a clipping mode that shows no glyph clips everything away',
        () async {
      final page = await _render(await _page('', renderMode: 7));

      expect(_count(page, _isRed), isZero);
      expect(_count(page, _isWhite), equals(page.width * page.height));
    });

    test('the text clip is undone by Q', () async {
      // The cover is painted after restoreState in _page only when the text
      // object and the cover share a state; here they are separated.
      final output = BytesBuilder(copy: false);
      final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
      final page = await pdf.appendBlankPage();
      page
          .pdfRepresentation()
          .put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, 320, 100]));
      final font = PdfTrueTypeFont(
          TrueTypeFont.fromFile(_fontPath), 'WinAnsiEncoding', true);
      final canvas = await PdfCanvas.fromPage(page);
      canvas.saveState();
      canvas.beginText();
      await canvas.setFontAndSize(font, 48);
      canvas.setTextRenderingMode(7);
      canvas.moveText(20, 30);
      canvas.showText('Hamburg');
      canvas.endText();
      canvas.restoreState();
      canvas.setFillColor(DeviceRgb(1, 0, 0));
      canvas.rectangle(0, 0, 320, 100);
      canvas.fill();
      await pdf.close();

      final rendered = await _render(output.takeBytes());
      expect(_count(rendered, _isRed),
          equals(rendered.width * rendered.height));
    });

    test('mode 2 fills and strokes the same glyphs', () async {
      final filled = await _render(await _page('Hamburg',
          renderMode: 0, coverAfterwards: false));
      final both = await _render(await _page('Hamburg',
          renderMode: 2, coverAfterwards: false, lineWidth: 2));

      // Mode 0 lays down fill only; mode 2 adds a stroke in another colour, so
      // both colours have to be present and the fill must survive.
      expect(_count(filled, _isGreen), isZero);
      expect(_count(both, _isGreen), greaterThan(100));
      expect(_count(both, _isBlue), greaterThan(100));
    });
  });
}
