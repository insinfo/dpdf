import 'dart:typed_data';
import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

typedef MutateOutline = void Function(List<CraftPdfDictionary> nodes);
Future<Uint8List> outlineSource({MutateOutline? mutate}) async {
  final bytes = BytesBuilder();
  final document =
      await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(bytes));
  final pages = [
    await document.appendBlankPage(),
    await document.appendBlankPage()
  ];
  CraftPdfDictionary node(String title, CraftPdfPage page) =>
      CraftPdfDictionary()
        ..attachToDocument(document)
        ..put(CraftPdfName('Title'), CraftPdfString(title))
        ..put(
            CraftPdfName('Dest'),
            CraftPdfArray.fromList(
                [page.pdfRepresentation(), CraftPdfName('Fit')]));
  final root = CraftPdfDictionary()
    ..attachToDocument(document)
    ..put(CraftPdfName.type, CraftPdfName('Outlines'));
  final first = node('Alpha', pages[0]);
  final last = node('Beta', pages[1]);
  final child = node('Detail', pages[1]);
  root
    ..put(CraftPdfName('First'), first)
    ..put(CraftPdfName('Last'), last)
    ..put(CraftPdfName('Count'), CraftPdfNumber.fromInt(2));
  first
    ..put(CraftPdfName.parent, root)
    ..put(CraftPdfName('Next'), last)
    ..put(CraftPdfName('First'), child)
    ..put(CraftPdfName('Last'), child)
    ..put(CraftPdfName('Count'), CraftPdfNumber.fromInt(-1))
    ..put(CraftPdfName('C'), CraftPdfArray.fromDoubles([0.2, 0.4, 0.6]))
    ..put(CraftPdfName('F'), CraftPdfNumber.fromInt(2));
  last
    ..put(CraftPdfName.parent, root)
    ..put(CraftPdfName('Prev'), first);
  child.put(CraftPdfName.parent, first);
  mutate?.call([first, last, child]);
  document
      .rootCatalog()
      .pdfRepresentation()
      .put(CraftPdfName('Outlines'), root);
  await document.close();
  return bytes.takeBytes();
}

Future<CraftPdfDocument> assemble(List<PdfPageSelection> sources) async =>
    CraftPdfDocument.open(CraftPdfReader.fromBytes(
        await PdfPageAssembly.merge(sources, preserveOutlines: true)));
Future<CraftPdfDictionary> outlineRoot(CraftPdfDocument document) async =>
    (await document
        .rootCatalog()
        .pdfRepresentation()
        .dictionaryEntry(CraftPdfName('Outlines')))!;
Future<CraftPdfDictionary> target(CraftPdfDictionary node) async =>
    (await (await node.arrayEntry(CraftPdfName('Dest')))!.dictionaryEntry(0))!;

void main() {
  test('Outline opt-in preserves hierarchy, titles, styles and closed state',
      () async {
    final bytes = await outlineSource();
    await expectLater(PdfPageAssembly.merge([PdfPageSelection(bytes)]),
        throwsUnsupportedError);
    final result = await assemble([PdfPageSelection(bytes)]);
    addTearDown(result.close);
    final root = await outlineRoot(result);
    final first = (await root.dictionaryEntry(CraftPdfName('First')))!;
    final child = (await first.dictionaryEntry(CraftPdfName('First')))!;
    expect(
        (await first.stringEntry(CraftPdfName('Title')))!.getValue(), 'Alpha');
    expect(
        (await child.stringEntry(CraftPdfName('Title')))!.getValue(), 'Detail');
    expect(identical(await child.dictionaryEntry(CraftPdfName.parent), first),
        isTrue);
    expect((await first.numberEntry(CraftPdfName('Count')))!.intValue(), -1);
    expect((await root.numberEntry(CraftPdfName('Count')))!.intValue(), 2);
    expect((await first.numberEntry(CraftPdfName('F')))!.intValue(), 2);
    expect((await first.arrayEntry(CraftPdfName('C')))!.size(), 3);
  });
  test('Reordered pages retarget explicit destinations', () async {
    final result = await assemble([
      PdfPageSelection(await outlineSource(), pages: [2, 1])
    ]);
    addTearDown(result.close);
    final first = (await (await outlineRoot(result))
        .dictionaryEntry(CraftPdfName('First')))!;
    final last = (await first.dictionaryEntry(CraftPdfName('Next')))!;
    expect(
        identical(
            await target(first), (await result.pageAt(2))!.pdfRepresentation()),
        isTrue);
    expect(
        identical(
            await target(last), (await result.pageAt(1))!.pdfRepresentation()),
        isTrue);
  });
  test('Repeated documents retain independent outline destinations', () async {
    final bytes = await outlineSource();
    final result =
        await assemble([PdfPageSelection(bytes), PdfPageSelection(bytes)]);
    addTearDown(result.close);
    var current = (await (await outlineRoot(result))
        .dictionaryEntry(CraftPdfName('First')))!;
    for (var index = 1; index <= 4; index++) {
      expect(
          identical(await target(current),
              (await result.pageAt(index))!.pdfRepresentation()),
          isTrue);
      if (index < 4)
        current = (await current.dictionaryEntry(CraftPdfName('Next')))!;
    }
  });
  test('Repeated page selection targets first copy and omitted targets reject',
      () async {
    final bytes = await outlineSource();
    final result = await assemble([
      PdfPageSelection(bytes, pages: [1, 1, 2])
    ]);
    addTearDown(result.close);
    final first = (await (await outlineRoot(result))
        .dictionaryEntry(CraftPdfName('First')))!;
    expect(
        identical(
            await target(first), (await result.pageAt(1))!.pdfRepresentation()),
        isTrue);
    await expectLater(
        assemble([
          PdfPageSelection(bytes, pages: [2])
        ]),
        throwsUnsupportedError);
  });
  test('Local GoTo action becomes a remapped explicit destination', () async {
    final bytes = await outlineSource(mutate: (nodes) {
      final destination = nodes.first.remove(CraftPdfName('Dest'));
      nodes.first.put(
          CraftPdfName('A'),
          CraftPdfDictionary()
            ..put(CraftPdfName('S'), CraftPdfName('GoTo'))
            ..put(CraftPdfName('D'), destination!));
    });
    final result = await assemble([PdfPageSelection(bytes)]);
    addTearDown(result.close);
    final first = (await (await outlineRoot(result))
        .dictionaryEntry(CraftPdfName('First')))!;
    expect(
        identical(
            await target(first), (await result.pageAt(1))!.pdfRepresentation()),
        isTrue);
  });
  test('Named destinations and cyclic outline siblings reject explicitly',
      () async {
    final named = await outlineSource(
        mutate: (nodes) =>
            nodes.first.put(CraftPdfName('Dest'), CraftPdfString('named')));
    await expectLater(
        assemble([PdfPageSelection(named)]), throwsUnsupportedError);
    final cycle = await outlineSource(
        mutate: (nodes) => nodes.first.put(CraftPdfName('Next'), nodes.first));
    await expectLater(
        assemble([PdfPageSelection(cycle)]), throwsFormatException);
  });
}
