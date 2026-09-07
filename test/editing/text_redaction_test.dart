import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

Uint8List bytes(String s) => Uint8List.fromList(ascii.encode(s));
List<PdfPositionedCharacter> positions(Uint8List content) =>
    PdfTextPositions.fromContent(content,
        decoder: (_, codes) => ascii.decode(codes), width: (_, code) => 600);
Future<Uint8List> fixture(List<String> contents,
    {String? prohibited, String? encoding}) async {
  final buffer = BytesBuilder();
  final doc = CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(buffer));
  CraftPdfStream.withBytes(bytes('UNREFERENCED_SECRET'), 0)
      .attachToDocument(doc);
  final font = CraftPdfDictionary()
    ..put(CraftPdfName.type, CraftPdfName.font)
    ..put(CraftPdfName.subtype, CraftPdfName('Type1'))
    ..put(CraftPdfName.baseFont, CraftPdfName('Courier'));
  if (encoding != null) font.put(CraftPdfName.encoding, CraftPdfName(encoding));
  final fonts = CraftPdfDictionary()..put(CraftPdfName('F1'), font);
  final resources = CraftPdfDictionary()..put(CraftPdfName.font, fonts);
  resources.attachToDocument(doc);
  for (final content in contents) {
    final page = await doc.appendBlankPage();
    page.pdfRepresentation().put(CraftPdfName.resources, resources);
    page.pdfRepresentation().put(
        CraftPdfName.contents, CraftPdfStream.withBytes(bytes(content), 0));
    if (prohibited != null) {
      page
          .pdfRepresentation()
          .put(CraftPdfName(prohibited), CraftPdfString('SECRET'));
    }
  }
  (await doc.documentDetails()).pdfRepresentation().clear();
  await doc.close();
  return buffer.takeBytes();
}

void main() {
  test('Redaction preserves Standard quotes and removes WinAnsi accented text',
      () async {
    final standard = await fixture(['BT /F1 12 Tf <2760534543524554> Tj ET']);
    final clean = await PdfTextRedaction.remove(
        standard, [const PdfTextRemoval(1, 'SECRET')]);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(clean));
    expect(await PdfTextExtraction.fromPage((await doc.pageAt(1))!), '’‘');
    await doc.close();
    final accented = await fixture(['BT /F1 12 Tf <61e7e36f2058> Tj ET'],
        encoding: 'WinAnsiEncoding');
    final removed = await PdfTextRedaction.remove(
        accented, [const PdfTextRemoval(1, 'ação')]);
    final reopened =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(removed));
    expect(await PdfTextExtraction.fromPage((await reopened.pageAt(1))!), ' X');
    await reopened.close();
    final quoteRemoved =
        await PdfTextRedaction.remove(standard, [const PdfTextRemoval(1, '’')]);
    final quoteDoc =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(quoteRemoved));
    expect(await PdfTextExtraction.fromPage((await quoteDoc.pageAt(1))!),
        '‘SECRET');
    await quoteDoc.close();
  });
  test('Positions include CTM, text matrix, char/word spacing, scale and rise',
      () {
    final result = positions(bytes(
        'q 2 0 0 2 100 200 cm BT /F1 10 Tf 1 Tc 2 Tw 50 Tz 3 Ts 1 0 0 1 10 20 Tm (A B) Tj ET Q'));
    expect(result[0].x, 120);
    expect(result[0].y, 246);
    expect(result[0].endX, 127);
    expect(result[1].x, 127);
    expect(result[1].endX, 136);
    expect(result[2].x, 136);
    expect(result[2].endX, 143);
  });
  test('TJ and text line operators retain exact baseline positions', () {
    final result = positions(bytes(
        'BT /F1 10 Tf 12 TL 10 20 Td [(A) 100 (B)] TJ (C) \' 2 1 (D) " ET'));
    expect(result.map((c) => c.x), [10, 15, 10, 10]);
    expect(result.map((c) => c.y), [20, 20, 8, -4]);
  });
  test('Redaction removes data structurally and preserves surviving positions',
      () async {
    const content =
        '% SECRET also present in comment\nq 0 1 -1 0 200 10 cm BT /F1 12 Tf 1 Tc 2 Tw 80 Tz 14 TL 1 0 0 1 30 40 Tm (before ) Tj [(SEC) 25 (RET)] TJ ( after) Tj ET Q';
    final source = await fixture([content, 'BT /F1 12 Tf (other page) Tj ET']);
    final removed = await PdfTextRedaction.remove(
        source, [const PdfTextRemoval(1, 'SECRET')]);
    expect(latin1.decode(removed), isNot(contains('SECRET')));
    expect(latin1.decode(source), contains('UNREFERENCED_SECRET'));
    expect(latin1.decode(removed), isNot(contains('UNREFERENCED_SECRET')));
    expect(latin1.decode(removed), isNot(contains('also present in comment')));
    expect(latin1.decode(removed), isNot(contains('/Prev')));
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(removed));
    expect(doc.pageTotal(), 2);
    final page = (await doc.pageAt(1))!;
    expect(await PdfTextExtraction.fromPage(page), 'before  after');
    expect(
        await PdfTextExtraction.fromPage((await doc.pageAt(2))!), 'other page');
    final before = positions(bytes(content));
    final after = positions(await page.contentPayload());
    final expected = [...before.take(7), ...before.skip(13)];
    expect(after.length, expected.length);
    for (var i = 0; i < after.length; i++) {
      expect(after[i].text, expected[i].text);
      expect(after[i].x, closeTo(expected[i].x, 1e-9));
      expect(after[i].y, closeTo(expected[i].y, 1e-9));
      expect(after[i].endX, closeTo(expected[i].endX, 1e-9));
      expect(after[i].endY, closeTo(expected[i].endY, 1e-9));
    }
    await doc.close();
  });
  test('All occurrences including overlap are removed', () async {
    final output = await PdfTextRedaction.remove(
        await fixture(['BT /F1 12 Tf (ABABA) Tj ET']),
        [const PdfTextRemoval(1, 'ABA')]);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(output));
    expect(await PdfTextExtraction.fromPage((await doc.pageAt(1))!), '');
    await doc.close();
  });
  test('Hex and octal matches span operators but not independent text objects',
      () async {
    final output = await PdfTextRedaction.remove(
        await fixture([
          r'BT /F1 12 Tf <5345> Tj (\103\122\105\124) Tj ( safe) Tj ET',
        ]),
        [const PdfTextRemoval(1, 'SECRET')]);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(output));
    expect(await PdfTextExtraction.fromPage((await doc.pageAt(1))!), ' safe');
    await doc.close();
    await expectLater(
        PdfTextRedaction.remove(
            await fixture([
              'BT /F1 12 Tf (SEC) Tj ET BT /F1 12 Tf (RET) Tj ET',
            ]),
            [const PdfTextRemoval(1, 'SECRET')]),
        throwsStateError);
  });
  test('A page not selected for removal retains shared text and resources',
      () async {
    final output = await PdfTextRedaction.remove(
        await fixture([
          'BT /F1 12 Tf (SECRET) Tj ET',
          'BT /F1 12 Tf (SECRET) Tj ET',
        ]),
        [const PdfTextRemoval(1, 'SECRET')]);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(output));
    expect(await PdfTextExtraction.fromPage((await doc.pageAt(1))!), '');
    expect(await PdfTextExtraction.fromPage((await doc.pageAt(2))!), 'SECRET');
    await doc.close();
  });
  test('Unsafe content and redundant data fail closed', () async {
    for (final extra in ['Annots', 'Metadata', 'PieceInfo']) {
      final source =
          await fixture(['BT /F1 12 Tf (SECRET) Tj ET'], prohibited: extra);
      expect(
          PdfTextRedaction.remove(source, [const PdfTextRemoval(1, 'SECRET')]),
          throwsUnsupportedError);
    }
    for (final content in [
      'BT /F1 12 Tf (SECRET) Tj ET /X Do',
      'BI',
      '/Span BDC',
      'BT /F1 12 Tf 3 Tr (SECRET) Tj ET'
    ]) {
      expect(
          PdfTextRedaction.remove(
              await fixture([content]), [const PdfTextRemoval(1, 'SECRET')]),
          throwsUnsupportedError);
    }
    expect(
        PdfTextRedaction.remove(await fixture(['BT /F1 12 Tf (safe) Tj ET']),
            [const PdfTextRemoval(1, 'SECRET')]),
        throwsStateError);
  });
}
