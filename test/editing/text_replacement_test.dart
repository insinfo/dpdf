import 'dart:convert';
import 'package:test/test.dart';
import 'package:pdfcraft/src/editing/pdf_text_extraction.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_reader.dart';
import 'text_redaction_test.dart' show fixture, positions, bytes;

void main() {
  test('Removal never inserts text supplied by a replacement subtype',
      () async {
    final result = await PdfTextRedaction.remove(
        await fixture(['BT /F1 12 Tf (ABC Z) Tj ET']),
        [const PdfTextReplacement(1, 'ABC', 'ignored 漢')]);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(result));
    expect(await PdfTextExtraction.fromPage((await doc.pageAt(1))!), ' Z');
    await doc.close();
  });
  test('Replacement uses initial state across later font size changes',
      () async {
    const content = 'BT /F1 10 Tf 1 Tc (A) Tj /F1 20 Tf 3 Tc (BCZ) Tj ET';
    final result = await PdfTextEditing.replace(
        await fixture([content]), [const PdfTextReplacement(1, 'ABC', 'XY')]);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(result));
    final after = positions(await (await doc.pageAt(1))!.contentPayload());
    final before = positions(bytes(content));
    expect(after.map((c) => c.text).join(), 'XYZ');
    expect(after[0].x, 0);
    expect(after[0].endX, 7);
    expect(after[1].x, 7);
    expect(after[2].x, closeTo(before.last.x, 1e-9));
    expect(after[2].endX, closeTo(before.last.endX, 1e-9));
    await doc.close();
  });
  test('Replacement spans TJ and retains all surviving rotated positions',
      () async {
    const content =
        'q 0 1 -1 0 200 10 cm BT /F1 12 Tf 1 Tc 2 Tw 80 Tz 3 Ts 1 0 0 1 30 40 Tm (A ) Tj [(SEC) 25 (RET)] TJ ( Z) Tj ET Q';
    final result = await PdfTextEditing.replace(await fixture([content]),
        [const PdfTextReplacement(1, 'SECRET', 'long new value')]);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(result));
    final page = (await doc.pageAt(1))!;
    expect(await PdfTextExtraction.fromPage(page), 'A long new value Z');
    expect(latin1.decode(result), isNot(contains('SECRET')));
    expect(latin1.decode(result), isNot(contains('UNREFERENCED_SECRET')));
    final before = positions(bytes(content));
    final after = positions(await page.contentPayload());
    final survivors = [...after.take(2), ...after.skip(16)];
    final expected = [...before.take(2), ...before.skip(8)];
    expect(survivors.length, expected.length);
    for (var i = 0; i < expected.length; i++) {
      expect(survivors[i].text, expected[i].text);
      expect(survivors[i].x, closeTo(expected[i].x, 1e-9));
      expect(survivors[i].y, closeTo(expected[i].y, 1e-9));
      expect(survivors[i].endX, closeTo(expected[i].endX, 1e-9));
      expect(survivors[i].endY, closeTo(expected[i].endY, 1e-9));
    }
    expect(after[2].x, closeTo(before[2].x, 1e-9));
    expect(after[2].y, closeTo(before[2].y, 1e-9));
    await doc.close();
  });
  test('Accents are encoded and matching never recurses into replacement',
      () async {
    final result = await PdfTextEditing.replace(
        await fixture(['BT /F1 12 Tf (old old) Tj ET'],
            encoding: 'WinAnsiEncoding'),
        [const PdfTextReplacement(1, 'old', 'old ação')]);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(result));
    expect(await PdfTextExtraction.fromPage((await doc.pageAt(1))!),
        'old ação old ação');
    await doc.close();
  });
  test('Empty replacement removes and multiple original requests work',
      () async {
    final result = await PdfTextEditing.replace(
        await fixture(['BT /F1 12 Tf (one two three) Tj ET']), [
      const PdfTextReplacement(1, 'one', ''),
      const PdfTextReplacement(1, 'two', 'one')
    ]);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(result));
    expect(
        await PdfTextExtraction.fromPage((await doc.pageAt(1))!), ' one three');
    await doc.close();
  });
  test('Overlapping occurrences and overlapping requests are rejected',
      () async {
    final source = await fixture(['BT /F1 12 Tf (ABABA) Tj ET']);
    await expectLater(
        PdfTextEditing.replace(
            source, [const PdfTextReplacement(1, 'ABA', 'x')]),
        throwsArgumentError);
    await expectLater(
        PdfTextEditing.replace(source, [
          const PdfTextReplacement(1, 'AB', 'x'),
          const PdfTextReplacement(1, 'BA', 'y')
        ]),
        throwsArgumentError);
  });
  test('Absent and unrepresentable replacements and unsupported pages fail',
      () async {
    final source = await fixture(['BT /F1 12 Tf (ABC) Tj ET']);
    await expectLater(
        PdfTextEditing.replace(
            source, [const PdfTextReplacement(1, 'missing', 'x')]),
        throwsStateError);
    await expectLater(
        PdfTextEditing.replace(
            source, [const PdfTextReplacement(1, 'ABC', '漢')]),
        throwsFormatException);
    await expectLater(
        PdfTextEditing.replace(
            await fixture(['BT /F1 12 Tf (ABC) Tj ET'], prohibited: 'Metadata'),
            [const PdfTextReplacement(1, 'ABC', 'x')]),
        throwsUnsupportedError);
  });
}
