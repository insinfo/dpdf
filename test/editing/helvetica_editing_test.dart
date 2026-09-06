import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pdfcraft/src/editing/pdf_text_extraction.dart';
import 'package:pdfcraft/src/editing/pdf_simple_encoding.dart';
import 'package:pdfcraft/src/editing/pdf_standard_font_metrics.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_reader.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_writer.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_name.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_dictionary.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_stream.dart';

Future<Uint8List> source(String content, String encoding) async {
  final data = BytesBuilder();
  final doc =
      await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(data));
  final page = await doc.appendBlankPage();
  final font = CraftPdfDictionary()
    ..put(CraftPdfName.type, CraftPdfName.font)
    ..put(CraftPdfName.subtype, CraftPdfName('Type1'))
    ..put(CraftPdfName.baseFont, CraftPdfName('Helvetica'));
  if (encoding == 'WinAnsiEncoding')
    font.put(CraftPdfName.encoding, CraftPdfName(encoding));
  page.pdfRepresentation()
    ..put(
        CraftPdfName.resources,
        CraftPdfDictionary()
          ..put(CraftPdfName.font,
              CraftPdfDictionary()..put(CraftPdfName('F1'), font)))
    ..put(CraftPdfName.contents,
        CraftPdfStream.withBytes(Uint8List.fromList(ascii.encode(content)), 0));
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
    expect(() => w(128, 'StandardEncoding'), throwsFormatException);
    expect(
        () =>
            PdfStandardFontMetrics.width('Times-Roman', 'StandardEncoding', 65),
        throwsUnsupportedError);
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
        final doc =
            await CraftPdfDocument.open(CraftPdfReader.fromBytes(output));
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
                .dictionaryEntry(CraftPdfName.resources))!
            .dictionaryEntry(CraftPdfName.font);
        expect(
            (await (await fonts!.dictionaryEntry(CraftPdfName('F1')))!
                    .nameEntry(CraftPdfName.baseFont))!
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
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(output));
    expect(await PdfTextExtraction.fromPage((await doc.pageAt(1))!), 'ação Z');
    await doc.close();
  });
}
