import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/dpdf.dart';

Future<Uint8List> source(
    {String? destinations, bool cyclicInheritance = false}) async {
  final data = BytesBuilder();
  final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(data));
  final pages = [await doc.appendBlankPage(), await doc.appendBlankPage()];
  final font = PdfFontFactory.createFont('Helvetica');
  for (var i = 0; i < pages.length; i++) {
    final canvas = await PdfCanvas.fromPage(pages[i]);
    canvas.beginText();
    await canvas.setFontAndSize(font, 12);
    canvas.moveText(25, 35).showText('Source ${i + 1}').endText();
  }
  final first = pages.first.pdfRepresentation();
  final parent = (await first.dictionaryEntry(PdfName.parent))!;
  parent.put(
      PdfName.resources, (await first.dictionaryEntry(PdfName.resources))!);
  parent.put(PdfName.mediaBox, PdfArray.fromDoubles([10, 20, 410, 620]));
  parent.put(PdfName.cropBox, PdfArray.fromDoubles([20, 30, 400, 610]));
  parent.put(PdfName.rotate, PdfNumber.fromInt(90));
  for (final page in pages) {
    for (final name in ['Resources', 'MediaBox', 'CropBox', 'Rotate']) {
      page.pdfRepresentation().remove(PdfName(name));
    }
  }
  if (destinations != null) {
    final catalog = doc.rootCatalog().pdfRepresentation();
    if (destinations == 'inline') {
      catalog.put(
          PdfName('Dests'),
          PdfDictionary()
            ..put(
                PdfName('A'),
                PdfDictionary()
                  ..put(PdfName('D'),
                      PdfArray.fromList([first, PdfName('Fit')]))));
    } else {
      catalog.put(
          PdfName('Names'),
          PdfDictionary()
            ..put(
                PdfName('Dests'),
                PdfDictionary()
                  ..put(PdfName('Names'),
                      PdfArray.fromList([PdfString('orphan')]))));
    }
  }
  if (cyclicInheritance) {
    final loop = PdfDictionary()..attachToDocument(doc);
    loop.put(PdfName.parent, loop);
    pages.first.pdfRepresentation().put(PdfName.parent, loop);
  }
  await doc.close();
  return data.takeBytes();
}

void main() {
  test('cyclic inherited resource ancestry fails explicitly', () async {
    final bytes = await source(cyclicInheritance: true);
    await expectLater(
      PdfPageAssembly.merge([
        PdfPageSelection(bytes, pages: [1])
      ]),
      throwsFormatException,
    );
  });

  test(
      'import inherited geometry then overlay loaded destination keeps siblings',
      () async {
    final merged = await PdfPageAssembly.merge([
      PdfPageSelection(await source(), pages: [2, 1, 2])
    ]);
    final bytes = BytesBuilder();
    final doc = PdfDocument(
        reader: PdfReader.fromBytes(merged),
        writer: PdfWriter.fromBytesBuilder(bytes));
    await doc.load();
    final page = (await doc.pageAt(1))!;
    for (final (name, expected) in [
      ('MediaBox', [10, 20, 410, 620]),
      ('CropBox', [20, 30, 400, 610])
    ]) {
      final box = (await page.pdfRepresentation().arrayEntry(PdfName(name)))!;
      expect(
          [for (var i = 0; i < 4; i++) (await box.numberEntry(i))!.intValue()],
          expected);
    }
    expect(
        (await page.pdfRepresentation().numberEntry(PdfName.rotate))!
            .intValue(),
        90);
    final overlay = await PdfPageOverlay.create(page);
    overlay.beginText();
    await overlay.setFontAndSize(PdfFontFactory.createFont('Helvetica'), 12);
    overlay.moveText(40, 50).showText('STAMP').endText();
    await doc.close();
    final reopened =
        await PdfDocument.open(PdfReader.fromBytes(bytes.takeBytes()));
    try {
      expect(await PdfTextExtraction.fromPage((await reopened.pageAt(1))!),
          contains('STAMP'));
      expect(await PdfTextExtraction.fromPage((await reopened.pageAt(1))!),
          contains('Source 2'));
      expect(await PdfTextExtraction.fromPage((await reopened.pageAt(2))!),
          contains('Source 1'));
      final repeated =
          await PdfTextExtraction.fromPage((await reopened.pageAt(3))!);
      expect(repeated, contains('Source 2'));
      expect(repeated, isNot(contains('STAMP')));
    } finally {
      await reopened.close();
    }
  });
  for (final kind in ['inline', 'odd']) {
    test('named destination $kind is explicitly rejected without loss',
        () async {
      final bytes = await source(destinations: kind);
      await expectLater(
          PdfPageAssembly.merge([PdfPageSelection(bytes)],
              preserveOutlines: true),
          throwsUnsupportedError);
    });
  }
}
