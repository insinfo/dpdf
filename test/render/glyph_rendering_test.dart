import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';
import 'package:test/test.dart';

const _fontPath = 'test/assets/ABeeZee-Regular.ttf';
const _cidCffBase64 =
    'AQAEAgABAgABAAhUZXN0Q0lEAAECAAEALB0AAAAAHQAAAAAdAAAAAAweHQAAAEgPHQAAAFgRHQAAAGoMJB0AAABNDCUAAAAAAAAqASwDAAIAAAAAAgEAAwADAgABAAIABQAIDiAKDiAKDgACAgABAAwAFx0AAAAGHQAAAIkSHQAAAAYdAAAApBIdAAAABhMAAQIAAQAPlZ8V74sFi/dcBSeLBQsdAAAABhMAAQIAAQAS98CzFffAiwWL+CQF+8CLBQs=';

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
  final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await pdf.appendBlankPage();
  page
      .pdfRepresentation()
      .put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, width, height]));

  final program = TrueTypeFont.fromFile(_fontPath);
  // The third argument embeds the program, which is what gives the renderer
  // outlines to draw.
  final font = PdfTrueTypeFont(program, 'WinAnsiEncoding', true);

  final canvas = await PdfCanvas.fromPage(page);
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

Future<PdfRenderedPage> _renderWithFallback(
    Uint8List bytes, PdfFontFallback fallback) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  try {
    return await PdfPageRenderer.render((await document.pageAt(1))!,
        options: PdfRenderOptions(dpi: 72, fontFallback: fallback));
  } finally {
    await document.close();
  }
}

Future<PdfRenderedPage> _render(Uint8List bytes, {double dpi = 72}) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
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

(int, int)? _inkVerticalExtent(PdfRenderedPage page) {
  int? top, bottom;
  for (var y = 0; y < page.height; y++) {
    for (var x = 0; x < page.width; x++) {
      if ((page.pixels[y * page.width + x] & 0xFF) >= 128) continue;
      if (top == null || y < top) top = y;
      if (bottom == null || y > bottom) bottom = y;
    }
  }
  return top == null ? null : (top, bottom!);
}

/// A page whose text uses a standard font, which carries no program.
Future<Uint8List> _pageWithStandardFont(String text) async {
  final output = BytesBuilder(copy: false);
  final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await pdf.appendBlankPage();
  page
      .pdfRepresentation()
      .put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, 320, 100]));
  final canvas = await PdfCanvas.fromPage(page);
  canvas.beginText();
  await canvas.setFontAndSize(pdf.defaultTypeface()!, 36);
  canvas.moveText(20, 40);
  canvas.showText(text);
  canvas.endText();
  await pdf.close();
  return output.takeBytes();
}

Future<Uint8List> _pageWithCidCff() async {
  final output = BytesBuilder(copy: false);
  final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await pdf.appendBlankPage();
  page
      .pdfRepresentation()
      .put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, 120, 100]));

  final program = PdfStream.withBytes(base64Decode(_cidCffBase64), 0)
    ..put(PdfName.subtype, PdfName('CIDFontType0C'));
  final descriptor = PdfDictionary()
    ..put(PdfName.type, PdfName('FontDescriptor'))
    ..put(PdfName.fontName, PdfName('TestCID'))
    ..put(PdfName.flags, PdfNumber.fromInt(4))
    ..put(PdfName('FontBBox'), PdfArray.fromDoubles([0, 0, 600, 440]))
    ..put(PdfName('ItalicAngle'), PdfNumber(0))
    ..put(PdfName('Ascent'), PdfNumber(440))
    ..put(PdfName('Descent'), PdfNumber(0))
    ..put(PdfName('CapHeight'), PdfNumber(440))
    ..put(PdfName('StemV'), PdfNumber(80))
    ..put(PdfName('FontFile3'), program);
  final descendant = PdfDictionary()
    ..put(PdfName.type, PdfName.font)
    ..put(PdfName.subtype, PdfName('CIDFontType0'))
    ..put(PdfName.baseFont, PdfName('TestCID'))
    ..put(
        PdfName('CIDSystemInfo'),
        PdfDictionary()
          ..put(PdfName('Registry'), PdfString('Adobe'))
          ..put(PdfName('Ordering'), PdfString('Identity'))
          ..put(PdfName('Supplement'), PdfNumber(0)))
    ..put(PdfName.fontDescriptor, descriptor)
    ..put(PdfName('DW'), PdfNumber(1000));
  final type0 = PdfDictionary()
    ..put(PdfName.type, PdfName.font)
    ..put(PdfName.subtype, PdfName('Type0'))
    ..put(PdfName.baseFont, PdfName('TestCID'))
    ..put(PdfName('Encoding'), PdfName('Identity-H'))
    ..put(PdfName('DescendantFonts'), PdfArray.fromList([descendant]));
  page.pdfRepresentation()
    ..put(
        PdfName.resources,
        PdfDictionary()
          ..put(PdfName.font, PdfDictionary()..put(PdfName('F0'), type0)))
    ..put(
        PdfName.contents,
        PdfStream.withBytes(
            Uint8List.fromList(latin1
                .encode('BT /F0 30 Tf 1 0 0 1 20 50 Tm <002A012C> Tj ET')),
            0));
  await pdf.close();
  return output.takeBytes();
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

    test('CIDFontType0 usa o charset CFF para mapear CID a GID', () async {
      final page = await _render(await _pageWithCidCff());
      final extent = _inkExtent(page);

      expect(page.report.glyphsSkipped, isZero);
      expect(page.report.isComplete, isTrue);
      expect(extent, isNotNull);
      expect(extent!.$1, lessThan(25),
          reason: 'CID 42 deve selecionar o GID 1, cuja caixa começa em 10');
      expect(extent.$2, greaterThan(58),
          reason:
              'CID 300 deve selecionar o GID 2 pelo charset não identidade');
    });

    test('puts the ink where the text was positioned', () async {
      final page = await _render(await _pageWithText('Hi', x: 200));
      final extent = _inkExtent(page);

      expect(extent, isNotNull);
      // Text starts at x=200 in a 320-point page, so nothing may land left of
      // it. This is what catches a text matrix composed in the wrong order.
      expect(extent!.$1, greaterThanOrEqualTo(195));
    });

    test('keeps TrueType ascenders above the PDF baseline', () async {
      final page = await _render(await _pageWithText('H'));
      final extent = _inkVerticalExtent(page)!;

      // PDF baseline y=40 maps to image row 60 on a 100-point page at 72 dpi.
      expect(extent.$1, lessThan(50));
      expect(extent.$2, lessThanOrEqualTo(61));
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

    test('draws a non-embedded font when the caller supplies one', () async {
      // A maioria dos documentos reais referencia ao menos uma fonte sem
      // carregá-la. Sem substituto o texto é posicionado mas não desenhado; com
      // ele, tem de aparecer tinta.
      final bytes = await _pageWithStandardFont('Hamburg');

      final without = await _render(bytes);
      expect(without.report.glyphsSkipped, greaterThan(0));
      expect(_inked(without), isZero,
          reason: 'sem substituto não há contorno nenhum para desenhar');

      final program = File(_fontPath).readAsBytesSync();
      final with_ =
          await _renderWithFallback(bytes, (request) async => program);

      expect(with_.report.glyphsSkipped, isZero,
          reason: 'com o substituto nada mais fica por desenhar');
      expect(_inked(with_), greaterThan(200),
          reason: 'sete glifos a 36pt têm de deixar tinta de verdade');
    });

    test('a substitute that returns null leaves the text reported', () async {
      final bytes = await _pageWithStandardFont('Hamburg');
      final page = await _renderWithFallback(bytes, (request) async => null);

      expect(page.report.glyphsSkipped, greaterThan(0));
      expect(_inked(page), isZero);
    });

    test('a substitute that throws does not take the page down', () async {
      // Um `fontFallback` que lê de disco pode falhar. Isso não pode custar
      // o resto da página, que desenha normalmente.
      final bytes = await _pageWithStandardFont('Hamburg');
      final page = await _renderWithFallback(
          bytes, (request) async => throw StateError('sem fonte'));

      expect(page.report.glyphsSkipped, greaterThan(0));
    });

    test('the request describes the font being substituted', () async {
      final bytes = await _pageWithStandardFont('Hamburg');
      PdfFontRequest? seen;
      await _renderWithFallback(bytes, (request) async {
        seen = request;
        return null;
      });

      expect(seen, isNotNull);
      expect(seen!.familyName, contains('Helvetica'));
      expect(seen!.composite, isFalse);
    });

    test('positions a standard font from its bundled metrics', () async {
      // Uma das catorze padrão pode omitir `/Widths`; o leitor tem de conhecer
      // as métricas. Sem isso todo avanço vira zero e a linha se empilha num
      // ponto só.
      final program = File(_fontPath).readAsBytesSync();
      final one = _inkExtent(await _renderWithFallback(
          await _pageWithStandardFont('I'), (r) async => program))!;
      final many = _inkExtent(await _renderWithFallback(
          await _pageWithStandardFont('IIIIIIII'), (r) async => program))!;

      expect(many.$2 - many.$1, greaterThan((one.$2 - one.$1) * 4),
          reason: 'sem as métricas AFM os oito glifos ficariam sobrepostos');
    });

    test('reports text as skipped when the font is not embedded', () async {
      // A base-14 font carries no program. Substituting a different typeface
      // would change the page, so the renderer says so instead.
      final output = BytesBuilder(copy: false);
      final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
      final page = await pdf.appendBlankPage();
      final canvas = await PdfCanvas.fromPage(page);
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
