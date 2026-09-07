import 'dart:convert';
import 'dart:typed_data';
import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

// Behavioral cases adapted from dart_pdf's loaded_document_round_trip_test.
// Only API calls/async lifecycle differ. Inputs are generated here.
void main() {
  test('inherited resources remain available without changing a sibling',
      () async {
    final output = BytesBuilder();
    final document = await _open(await _source(), output);
    final page = (await document.pageAt(1))!;
    final sibling = (await document.pageAt(2))!;
    final parent =
        await page.pdfRepresentation().dictionaryEntry(CraftPdfName.parent);
    final inherited =
        await page.pdfRepresentation().dictionaryEntry(CraftPdfName.resources);
    parent!.put(CraftPdfName.resources, inherited!);
    page.pdfRepresentation().remove(CraftPdfName.resources);
    sibling.pdfRepresentation().remove(CraftPdfName.resources);
    await _draw(page, 'LOCAL');
    expect(
        await parent.dictionaryEntry(CraftPdfName.resources), same(inherited));
    expect(inherited.containsKey(CraftPdfName.xObject), isFalse);
    await document.close();
    final reopened = await CraftPdfDocument.open(
        CraftPdfReader.fromBytes(output.takeBytes()));
    try {
      expect(await PdfTextExtraction.fromPage((await reopened.pageAt(1))!),
          contains('LOCAL'));
      expect(await PdfTextExtraction.fromPage((await reopened.pageAt(2))!),
          contains('Page 2'));
    } finally {
      await reopened.close();
    }
  });

  test('state envelope ignores operator-like bytes inside lexical values', () {
    final source = Uint8List.fromList(latin1
        .encode('% q Q\n /q (q Q) <7151> [(Q)] << /Q (q) >> q 1 0 0 1 2 3 cm'));
    final wrapped = latin1.decode(PdfGraphicsEnvelope.wrap(source));
    expect(wrapped, startsWith('q\n'));
    expect(wrapped, endsWith('\nQ\nQ\n'));
    expect(
        () => PdfGraphicsEnvelope.wrap(Uint8List.fromList('BI /W 1'.codeUnits)),
        throwsUnsupportedError);
  });

  test('append drawing retains original content and changes only its page',
      () async {
    final bytes = await _source();
    final output = BytesBuilder();
    final document = await _open(bytes, output);
    await _draw((await document.pageAt(1))!, 'OVERLAY');
    await document.close();
    final result = await CraftPdfDocument.open(
        CraftPdfReader.fromBytes(output.takeBytes()));
    try {
      expect(await PdfTextExtraction.fromPage((await result.pageAt(1))!),
          contains('OVERLAY'));
      expect(await PdfTextExtraction.fromPage((await result.pageAt(1))!),
          contains('Page 1'));
      expect(await PdfTextExtraction.fromPage((await result.pageAt(2))!),
          isNot(contains('OVERLAY')));
    } finally {
      await result.close();
    }
  });

  test('independent drawing contexts work repeatedly and after reopening',
      () async {
    var bytes = await _source();
    for (final labels in [
      ['FIRST', 'SECOND'],
      ['THIRD']
    ]) {
      final output = BytesBuilder();
      final document = await _open(bytes, output);
      final page = (await document.pageAt(1))!;
      for (final label in labels) {
        await _draw(page, label);
      }
      await document.close();
      bytes = output.takeBytes();
    }
    final result = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      final text = await PdfTextExtraction.fromPage((await result.pageAt(1))!);
      for (final label in ['Page 1', 'FIRST', 'SECOND', 'THIRD']) {
        expect(text, contains(label));
      }
    } finally {
      await result.close();
    }
  });

  test('original unbalanced transform stays inside its own form', () async {
    final output = BytesBuilder();
    final document = await _open(await _source(unbalanced: true), output);
    final page = (await document.pageAt(1))!;
    await _draw(page, 'GUARDED');
    final operators = latin1.decode(await page.contentPayload());
    expect(operators, isNot(contains(' cm')));
    expect(RegExp(r'\bDo\b').allMatches(operators).length, 2);
    final resources = await page.resourceDirectory();
    final objects = await resources
        .pdfRepresentation()
        .dictionaryEntry(CraftPdfName.xObject);
    final forms = await objects!.entrySet();
    final payloads = <String>[];
    for (final entry in forms) {
      payloads.add(
          latin1.decode((await (entry.value as CraftPdfStream).getBytes())!));
    }
    expect(payloads.where((p) => p.contains('300 400 cm')).length, 1);
    expect(payloads.where((p) => p.contains('GUARDED')).single,
        isNot(contains('300 400 cm')));
    await document.close();
    final reopened = await CraftPdfDocument.open(
        CraftPdfReader.fromBytes(output.takeBytes()));
    try {
      expect(await PdfTextExtraction.fromPage((await reopened.pageAt(1))!),
          contains('GUARDED'));
    } finally {
      await reopened.close();
    }
  });
}

Future<CraftPdfDocument> _open(Uint8List bytes, BytesBuilder output) async {
  final document = CraftPdfDocument(
      reader: CraftPdfReader.fromBytes(bytes),
      writer: CraftPdfWriter.fromBytesBuilder(output));
  await document.load();
  return document;
}

Future<void> _draw(CraftPdfPage page, String text) async {
  final canvas = await PdfPageOverlay.create(page);
  canvas.beginText();
  await canvas.setFontAndSize(
      await CraftPdfFontFactory.createFont('Helvetica'), 18);
  canvas.moveText(20, 40).showText(text).endText();
}

Future<Uint8List> _source({bool unbalanced = false}) async {
  final output = BytesBuilder();
  final document =
      CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(output));
  for (var index = 1; index <= 2; index++) {
    final page = await document.appendBlankPage();
    final canvas = await CraftPdfCanvas.fromPage(page);
    if (unbalanced && index == 1) {
      canvas.contentStream!
          .getOutputStream()
          .writeBytes(ascii.encode('q 2 0 0 2 300 400 cm\n'));
    }
    canvas.beginText();
    await canvas.setFontAndSize(
        await CraftPdfFontFactory.createFont('Helvetica'), 18);
    canvas.moveText(50, 100).showText('Page $index').endText();
  }
  await document.close();
  return output.takeBytes();
}
