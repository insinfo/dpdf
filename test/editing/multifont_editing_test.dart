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

Future<Uint8List> source(List<String> contents,
    {String firstBase = 'Courier'}) async {
  final bytes = BytesBuilder();
  final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
  for (var i = 0; i < contents.length; i++) {
    final page = await doc.appendBlankPage();
    final fonts = PdfDictionary();
    for (final (name, base, encoding) in [
      ('Body Space', i == 0 ? firstBase : 'Helvetica', 'StandardEncoding'),
      ('Accent', 'Helvetica', 'WinAnsiEncoding'),
    ]) {
      fonts.put(
          PdfName(name),
          PdfDictionary()
            ..put(PdfName.type, PdfName.font)
            ..put(PdfName.subtype, PdfName('Type1'))
            ..put(PdfName.baseFont, PdfName(base))
            ..put(PdfName.encoding, PdfName(encoding)));
    }
    page.pdfRepresentation()
      ..put(PdfName.resources, PdfDictionary()..put(PdfName.font, fonts))
      ..put(
          PdfName.contents,
          PdfStream.withBytes(
              Uint8List.fromList(ascii.encode(contents[i])), 0));
  }
  (await doc.documentDetails()).pdfRepresentation().clear();
  await doc.close();
  return bytes.takeBytes();
}

List<PdfPositionedCharacter> positions(Uint8List content) =>
    PdfTextPositions.fromContent(content,
        decoder: (font, bytes) => PdfSimpleEncoding.decode(
            (font == 'Accent' || font == 'F2')
                ? 'WinAnsiEncoding'
                : 'StandardEncoding',
            bytes),
        width: (font, code) => PdfStandardFontMetrics.width(
            (font == 'Accent' || font == 'F2') ? 'Helvetica' : 'Courier',
            (font == 'Accent' || font == 'F2')
                ? 'WinAnsiEncoding'
                : 'StandardEncoding',
            code));

void main() {
  for (final replace in [false, true]) {
    test(
        'cross-font ${replace ? 'replacement' : 'removal'} preserves survivors',
        () async {
      const content =
          'q 0 1 -1 0 150 10 cm BT /Body#20Space 12 Tf 1 Tc 2 Tw 80 Tz 3 Ts 30 40 Td (A SEC) Tj /Accent 19 Tf [(RE) 25 (T)] TJ ( Z) Tj ET Q';
      final input = await source([content]);
      final output = replace
          ? await PdfTextEditing.replace(
              input, [const PdfTextReplacement(1, 'SECRET', 'NEW')])
          : await PdfTextRedaction.remove(
              input, [const PdfTextRemoval(1, 'SECRET')]);
      final doc = await PdfDocument.open(PdfReader.fromBytes(output));
      final page = (await doc.pageAt(1))!;
      expect(
          await PdfTextExtraction.fromPage(page), replace ? 'A NEW Z' : 'A  Z');
      final before = positions(Uint8List.fromList(ascii.encode(content)));
      final after = positions(await page.contentPayload());
      final expected = [...before.take(2), ...before.skip(8)];
      final actual = [...after.take(2), ...after.skip(replace ? 5 : 2)];
      for (var i = 0; i < expected.length; i++) {
        expect(actual[i].font, expected[i].font == 'Accent' ? 'F2' : 'F1');
        expect(actual[i].x, closeTo(expected[i].x, 1e-8));
        expect(actual[i].y, closeTo(expected[i].y, 1e-8));
        expect(actual[i].endX, closeTo(expected[i].endX, 1e-8));
        expect(actual[i].endY, closeTo(expected[i].endY, 1e-8));
      }
      expect(latin1.decode(output), isNot(contains('SECRET')));
      final fonts = await (await page
              .pdfRepresentation()
              .dictionaryEntry(PdfName.resources))!
          .dictionaryEntry(PdfName.font);
      expect(fonts!.size(), 2);
      expect(fonts.containsKey(PdfName('F1')), isTrue);
      expect(latin1.decode(output), isNot(contains('Body')));
      await doc.close();
    });
  }
  test(
      'replacement uses first matched font encoding and page-local font resources',
      () async {
    final input = await source([
      'BT /Accent 12 Tf (old) Tj /Body#20Space 12 Tf ( end) Tj ET',
      'BT /Body#20Space 12 Tf (old Z) Tj ET',
    ]);
    final output = await PdfTextEditing.replace(input, [
      const PdfTextReplacement(1, 'old', 'ação'),
      const PdfTextReplacement(2, 'old', 'NEW'),
    ]);
    final doc = await PdfDocument.open(PdfReader.fromBytes(output));
    expect(
        await PdfTextExtraction.fromPage((await doc.pageAt(1))!), 'ação end');
    expect(await PdfTextExtraction.fromPage((await doc.pageAt(2))!), 'NEW Z');
    for (var n = 1; n <= 2; n++) {
      final page = (await doc.pageAt(n))!;
      final fonts = await (await page
              .pdfRepresentation()
              .dictionaryEntry(PdfName.resources))!
          .dictionaryEntry(PdfName.font);
      final font = (await fonts!.dictionaryEntry(PdfName('F1')))!;
      expect((await font.nameEntry(PdfName.baseFont))!.getValue(),
          n == 1 ? 'Courier' : 'Helvetica');
    }
    await doc.close();
  });
  test('dictionary names round trip escaped delimiters and byte values',
      () async {
    final bytes = BytesBuilder();
    final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
    final page = await document.appendBlankPage();
    const key = 'Space #/é';
    const value = 'Value #[]é';
    page.pdfRepresentation().put(PdfName(key), PdfName(value));
    await document.close();
    final output = bytes.takeBytes();
    expect(latin1.decode(output), contains('/Space#20#23#2F#E9'));
    final read = await PdfDocument.open(PdfReader.fromBytes(output));
    expect(
        (await (await read.pageAt(1))!
                .pdfRepresentation()
                .nameEntry(PdfName(key)))!
            .getValue(),
        value);
    await read.close();
  });
  test('unsupported extra font is rejected before rebuilding', () async {
    final input = await source(['BT /Accent 12 Tf (old) Tj ET'],
        firstBase: 'Times-Roman');
    await expectLater(
        PdfTextRedaction.remove(input, [const PdfTextRemoval(1, 'old')]),
        throwsUnsupportedError);
  });
  test('undeclared font resource is rejected', () async {
    final input = await source(['BT /Missing 12 Tf (old) Tj ET']);
    await expectLater(
        PdfTextRedaction.remove(input, [const PdfTextRemoval(1, 'old')]),
        throwsUnsupportedError);
  });
}
