import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/editing/pdf_simple_encoding.dart';
import 'package:dpdf/src/editing/pdf_standard_font_metrics.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';

Future<Uint8List> source(String content, String encoding) async {
  final data = BytesBuilder();
  final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(data));
  final page = await doc.appendBlankPage();
  final font = PdfDictionary()
    ..put(PdfName.type, PdfName.font)
    ..put(PdfName.subtype, PdfName('Type1'))
    ..put(PdfName.baseFont, PdfName('Helvetica'));
  if (encoding == 'WinAnsiEncoding') {
    font.put(PdfName.encoding, PdfName(encoding));
  }
  page.pdfRepresentation()
    ..put(
        PdfName.resources,
        PdfDictionary()
          ..put(PdfName.font, PdfDictionary()..put(PdfName('F1'), font)))
    ..put(PdfName.contents,
        PdfStream.withBytes(Uint8List.fromList(ascii.encode(content)), 0));
  (await doc.documentDetails()).pdfRepresentation().clear();
  await doc.close();
  return data.takeBytes();
}

void main() {
  test('Helvetica AFM widths distinguish glyphs and encoding aliases', () {
    double w(int code, [String e = 'WinAnsiEncoding']) =>
        PdfStandardFontMetrics.width('Helvetica', e, code);
    expect(w(87), 944);
    expect(w(105), 222);
    expect(w(32), 278);
    expect(w(160), 278);
    expect(w(173), 333);
    expect(w(181), 556);
    expect(w(39, 'StandardEncoding'), 222);
    expect(w(39), 191);
    // Byte 128 is undefined in StandardEncoding, so the face has no metric
    // for it.
    expect(() => w(128, 'StandardEncoding'), throwsUnsupportedError);
    expect(
        () => PdfStandardFontMetrics.width('NoSuchFace', 'WinAnsiEncoding', 65),
        throwsUnsupportedError);
  });

  test('All fourteen standard faces are measurable', () {
    double w(String font, int code) =>
        PdfStandardFontMetrics.width(font, 'WinAnsiEncoding', code);

    expect(PdfStandardFontMetrics.availableFonts, hasLength(14));
    for (final font in PdfStandardFontMetrics.availableFonts) {
      expect(PdfStandardFontMetrics.supports(font), isTrue, reason: font);
    }

    // Capital A, straight from each AFM.
    expect(w('Times-Roman', 65), 722);
    expect(w('Times-Bold', 65), 722);
    expect(w('Times-Italic', 65), 611);
    expect(w('Helvetica-Bold', 65), 722);
    expect(w('Courier', 65), 600);
    // Courier is monospaced: every glyph advances the same.
    expect(w('Courier', 105), 600);
    expect(w('Courier-BoldOblique', 87), 600);
    // The two symbolic faces answer through their own built-in encoding.
    expect(w('Symbol', 65), 722);
    expect(w('ZapfDingbats', 97), 789);
  });

  test('Text width sums the advances of a whole string', () {
    expect(
        PdfStandardFontMetrics.textWidth(
            'Times-Roman', 'WinAnsiEncoding', 'AV', 10),
        closeTo((722 + 722) / 1000 * 10, 1e-9));
    expect(
        PdfStandardFontMetrics.textWidth(
            'Courier', 'WinAnsiEncoding', 'abcd', 12),
        closeTo(600 * 4 / 1000 * 12, 1e-9));
    expect(
        PdfStandardFontMetrics.textWidth(
            'Helvetica', 'WinAnsiEncoding', '', 12),
        isZero);
  });
  for (final encoding in ['StandardEncoding', 'WinAnsiEncoding']) {
    for (final replacement in [false, true]) {
      test(
          '$encoding Helvetica ${replacement ? 'replace' : 'remove'} preserves surviving positions',
          () async {
        const content =
            'q 0 1 -1 0 150 10 cm BT /F1 12 Tf 1 Tc 2 Tw 80 Tz 3 Ts 1 0 0 1 30 40 Tm (Wi ) Tj [(SEC) 25 (RET)] TJ ( Z) Tj ET Q';
        List<PdfPositionedCharacter> positions(Uint8List data) =>
            PdfTextPositions.fromContent(data,
                decoder: (_, codes) =>
                    PdfSimpleEncoding.decode(encoding, codes),
                width: (_, code) =>
                    PdfStandardFontMetrics.width('Helvetica', encoding, code));
        final input = await source(content, encoding);
        final output = replacement
            ? await PdfTextEditing.replace(
                input, [const PdfTextReplacement(1, 'SECRET', 'iiiWWW')])
            : await PdfTextRedaction.remove(
                input, [const PdfTextRemoval(1, 'SECRET')]);
        final doc = await PdfDocument.open(PdfReader.fromBytes(output));
        final page = (await doc.pageAt(1))!;
        final after = positions(await page.contentPayload());
        final before = positions(Uint8List.fromList(ascii.encode(content)));
        expect(await PdfTextExtraction.fromPage(page),
            replacement ? 'Wi iiiWWW Z' : 'Wi  Z');
        final survivors = [
          ...after.take(3),
          ...after.skip(replacement ? 9 : 3)
        ];
        final original = [...before.take(3), ...before.skip(9)];
        for (var i = 0; i < original.length; i++) {
          expect(survivors[i].x, closeTo(original[i].x, 1e-9));
          expect(survivors[i].y, closeTo(original[i].y, 1e-9));
          expect(survivors[i].endX, closeTo(original[i].endX, 1e-9));
          expect(survivors[i].endY, closeTo(original[i].endY, 1e-9));
        }
        final fonts = await (await page
                .pdfRepresentation()
                .dictionaryEntry(PdfName.resources))!
            .dictionaryEntry(PdfName.font);
        expect(
            (await (await fonts!.dictionaryEntry(PdfName('F1')))!
                    .nameEntry(PdfName.baseFont))!
                .getValue(),
            'Helvetica');
        expect(latin1.decode(output), isNot(contains('SECRET')));
        await doc.close();
      });
    }
  }
  test('WinAnsi Helvetica accents survive replacement encoding', () async {
    final output = await PdfTextEditing.replace(
        await source('BT /F1 12 Tf (old Z) Tj ET', 'WinAnsiEncoding'),
        [const PdfTextReplacement(1, 'old', 'ação')]);
    final doc = await PdfDocument.open(PdfReader.fromBytes(output));
    expect(await PdfTextExtraction.fromPage((await doc.pageAt(1))!), 'ação Z');
    await doc.close();
  });
}
