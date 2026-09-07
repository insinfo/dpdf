import 'dart:convert';
import 'dart:typed_data';
import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

typedef Configure = void Function(CraftPdfDocument document,
    List<CraftPdfPage> pages, List<CraftPdfDictionary> annotations);

Future<Uint8List> source({Configure? configure}) async {
  final bytes = BytesBuilder();
  final document =
      await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(bytes));
  final pages = [
    await document.appendBlankPage(),
    await document.appendBlankPage()
  ];
  CraftPdfDictionary annotation(String subtype, String contents) =>
      CraftPdfDictionary()
        ..put(CraftPdfName.type, CraftPdfName('Annot'))
        ..put(CraftPdfName.subtype, CraftPdfName(subtype))
        ..put(CraftPdfName.rect, CraftPdfArray.fromInts([10, 20, 80, 90]))
        ..put(CraftPdfName.contents, CraftPdfString(contents))
        ..put(CraftPdfName('P'), pages.first.pdfRepresentation())
        ..attachToDocument(document);
  final square = annotation('Square', 'local rectangle');
  final link = annotation('Link', 'external link')
    ..put(
        CraftPdfName('A'),
        CraftPdfDictionary()
          ..put(CraftPdfName('S'), CraftPdfName('URI'))
          ..put(CraftPdfName('URI'),
              CraftPdfString('https://example.org/fixture')));
  final note = annotation('Text', 'review note');
  final popup = annotation('Popup', 'popup');
  note.put(CraftPdfName('Popup'), popup);
  popup.put(CraftPdfName.parent, note);
  final appearance = CraftPdfStream.withBytes(
      Uint8List.fromList(ascii.encode('0 0 20 20 re S')), 0)
    ..put(CraftPdfName.subtype, CraftPdfName('Form'))
    ..put(CraftPdfName('BBox'), CraftPdfArray.fromInts([0, 0, 20, 20]));
  square.put(CraftPdfName('AP'),
      CraftPdfDictionary()..put(CraftPdfName('N'), appearance));
  final annotations = [square, link, note, popup];
  pages.first
      .pdfRepresentation()
      .put(CraftPdfName.annots, CraftPdfArray.fromList(annotations));
  configure?.call(document, pages, annotations);
  await document.close();
  return bytes.takeBytes();
}

Future<CraftPdfDocument> merged(Uint8List sourceBytes,
        {List<int> pages = const [1]}) async =>
    CraftPdfDocument.open(CraftPdfReader.fromBytes(await PdfPageAssembly.merge(
        [PdfPageSelection(sourceBytes, pages: pages)],
        includeAnnotations: true)));

void main() {
  test(
      'Static annotation import is explicit; strict default still rejects annotations',
      () async {
    final bytes = await source();
    await expectLater(PdfPageAssembly.merge([PdfPageSelection(bytes)]),
        throwsUnsupportedError);
    final result = await merged(bytes);
    addTearDown(result.close);
    final annotations = (await (await result.pageAt(1))!
        .pdfRepresentation()
        .arrayEntry(CraftPdfName.annots))!;
    expect(annotations.size(), 4);
    expect(
        (await (await annotations.dictionaryEntry(0))!
                .stringEntry(CraftPdfName.contents))!
            .getValue(),
        'local rectangle');
  });
  test('URI targets and normal appearance streams survive serialization',
      () async {
    final result = await merged(await source());
    addTearDown(result.close);
    final annotations = (await (await result.pageAt(1))!
        .pdfRepresentation()
        .arrayEntry(CraftPdfName.annots))!;
    final link = (await annotations.dictionaryEntry(1))!;
    final action = (await link.dictionaryEntry(CraftPdfName('A')))!;
    expect((await action.stringEntry(CraftPdfName('URI')))!.getValue(),
        'https://example.org/fixture');
    final square = (await annotations.dictionaryEntry(0))!;
    final appearances = (await square.dictionaryEntry(CraftPdfName('AP')))!;
    final appearance = (await appearances.streamEntry(CraftPdfName('N')))!;
    expect(ascii.decode((await appearance.getBytes())!), '0 0 20 20 re S');
    expect((await square.arrayEntry(CraftPdfName.rect))!.size(), 4);
  });
  test(
      'Repeated page selections isolate annotation objects and popup relationships',
      () async {
    final result = await merged(await source(), pages: [1, 1]);
    addTearDown(result.close);
    CraftPdfDictionary? firstNote;
    for (var index = 1; index <= 2; index++) {
      final page = (await result.pageAt(index))!.pdfRepresentation();
      final annotations = (await page.arrayEntry(CraftPdfName.annots))!;
      final note = (await annotations.dictionaryEntry(2))!;
      final popup = (await annotations.dictionaryEntry(3))!;
      expect(identical(await note.dictionaryEntry(CraftPdfName('P')), page),
          isTrue);
      expect(identical(await popup.dictionaryEntry(CraftPdfName.parent), note),
          isTrue);
      expect(
          identical(await note.dictionaryEntry(CraftPdfName('Popup')), popup),
          isTrue);
      if (firstNote != null) expect(identical(firstNote, note), isFalse);
      firstNote = note;
    }
  });
  test('Selected blank pages do not acquire annotations from omitted pages',
      () async {
    final result = await merged(await source(), pages: [2]);
    addTearDown(result.close);
    expect(
        (await result.pageAt(1))!
            .pdfRepresentation()
            .containsKey(CraftPdfName.annots),
        isFalse);
  });
  test('Widgets and internal link destinations fail explicitly', () async {
    final widget = await source(
        configure: (_, __, annotations) => annotations.first
            .put(CraftPdfName.subtype, CraftPdfName('Widget')));
    await expectLater(merged(widget), throwsUnsupportedError);
    final destination = await source(
        configure: (_, pages, annotations) => annotations[1].put(
            CraftPdfName('Dest'),
            CraftPdfArray.withObject(pages[1].pdfRepresentation())));
    await expectLater(merged(destination), throwsUnsupportedError);
  });
  test('Cross-page owners and popup parents are not silently imported',
      () async {
    final wrongPage = await source(
        configure: (_, pages, annotations) => annotations.first
            .put(CraftPdfName('P'), pages[1].pdfRepresentation()));
    await expectLater(merged(wrongPage), throwsUnsupportedError);
    final wrongParent = await source(
        configure: (_, pages, annotations) => annotations[3]
            .put(CraftPdfName.parent, pages[1].pdfRepresentation()));
    await expectLater(merged(wrongParent), throwsUnsupportedError);
  });
  test('URI action chains and hidden foreign-page references are rejected',
      () async {
    final chain = await source(
        configure: (_, __, annotations) => annotations[1].put(
            CraftPdfName('A'),
            CraftPdfDictionary()
              ..put(CraftPdfName('S'), CraftPdfName('URI'))
              ..put(CraftPdfName('URI'), CraftPdfString('https://example.org/'))
              ..put(CraftPdfName('Next'), CraftPdfDictionary())));
    await expectLater(merged(chain), throwsUnsupportedError);
    final foreign = await source(
        configure: (_, pages, annotations) => annotations.first
            .put(CraftPdfName('PrivateData'), pages[1].pdfRepresentation()));
    await expectLater(merged(foreign), throwsUnsupportedError);
  });
}
