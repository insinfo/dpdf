import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';
import 'package:dpdf/src/kernel/pdf/extgstate/pdf_ext_g_state.dart';
import 'package:test/test.dart';

const _fontPath = 'test/assets/ABeeZee-Regular.ttf';

/// A page showing two glyphs pushed on top of each other by a large negative
/// character spacing, painted at [alpha].
///
/// Overlapping semi-transparent glyphs are the only place text knockout is
/// visible: at alpha 1 the knockout and non-knockout results are identical.
Future<Uint8List> _overlappingText({
  required bool? textKnockout,
  double alpha = 0.5,
}) async {
  final output = BytesBuilder(copy: false);
  final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await pdf.appendBlankPage();
  page
      .pdfRepresentation()
      .put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, 200, 100]));

  final font = PdfTrueTypeFont(
      TrueTypeFont.fromFile(_fontPath), 'WinAnsiEncoding', true);

  final canvas = await PdfCanvas.fromPage(page);
  final gs = PdfExtGState()..setFillOpacity(alpha);
  if (textKnockout != null) {
    gs.pdfRepresentation().put(PdfName('TK'), PdfBoolean(textKnockout));
  }
  await canvas.setExtGState(gs);
  canvas.beginText();
  await canvas.setFontAndSize(font, 72);
  canvas.setCharacterSpacing(-40);
  canvas.moveText(20, 25);
  canvas.showText('HH');
  canvas.endText();

  await pdf.close();
  return output.takeBytes();
}

Future<PdfRenderedPage> _render(Uint8List bytes) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  try {
    return await PdfPageRenderer.render(
      (await document.pageAt(1))!,
      options: const PdfRenderOptions(dpi: 72),
    );
  } finally {
    await document.close();
  }
}

/// The darkest red channel anywhere on the page.
///
/// Grey text on white: the darkest pixel is the most heavily painted one, so
/// this is where overlapping glyphs would have compounded.
int _darkest(PdfRenderedPage page) {
  var darkest = 255;
  for (final word in page.pixels) {
    final red = (word >> 16) & 0xff;
    if (red < darkest) darkest = red;
  }
  return darkest;
}

void main() {
  group('text knockout, clause 9.3.8', () {
    late int knockedOut;
    late int stacked;

    setUpAll(() async {
      knockedOut =
          _darkest(await _render(await _overlappingText(textKnockout: true)));
      stacked =
          _darkest(await _render(await _overlappingText(textKnockout: false)));
    });

    test('overlapping glyphs do not compound when /TK is true', () async {
      // One glyph at alpha 0.5 over white is 0x80. Knocked out, the overlap
      // of two glyphs is still one element, so it stays at 0x80 rather than
      // darkening to 0.5 + 0.5 * 0.5 = 0x40.
      expect(knockedOut, closeTo(127, 3));
    });

    test('/TK false composites each glyph with the last', () async {
      expect(stacked, closeTo(64, 4));
      expect(stacked, lessThan(knockedOut - 30));
    });

    test('/TK defaults to true', () async {
      final byDefault =
          _darkest(await _render(await _overlappingText(textKnockout: null)));
      expect(byDefault, equals(knockedOut));
    });

    test('opaque text renders the same either way', () async {
      // With alpha 1 knockout cannot change anything, which is what lets the
      // renderer skip the offscreen layer for ordinary text.
      final on =
          await _render(await _overlappingText(textKnockout: true, alpha: 1));
      final off =
          await _render(await _overlappingText(textKnockout: false, alpha: 1));
      expect(on.pixels, equals(off.pixels));
    });

    test('knockout ends with the text object', () async {
      // A second, separate text object composites with the first: the
      // knockout element is one text object, not the whole page.
      final output = BytesBuilder(copy: false);
      final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
      final page = await pdf.appendBlankPage();
      page
          .pdfRepresentation()
          .put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, 200, 100]));
      final font = PdfTrueTypeFont(
          TrueTypeFont.fromFile(_fontPath), 'WinAnsiEncoding', true);
      final canvas = await PdfCanvas.fromPage(page);
      await canvas.setExtGState(PdfExtGState()..setFillOpacity(0.5));
      for (var i = 0; i < 2; i++) {
        canvas.beginText();
        await canvas.setFontAndSize(font, 72);
        canvas.moveText(20, 25);
        canvas.showText('H');
        canvas.endText();
      }
      await pdf.close();

      final twice = _darkest(await _render(output.takeBytes()));
      expect(twice, closeTo(64, 4));
    });
  });
}
