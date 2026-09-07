import 'dart:typed_data';
import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

typedef MutateOutline = void Function(List<PdfDictionary> nodes);
Future<Uint8List> outlineSource({MutateOutline? mutate}) async {
  final bytes = BytesBuilder();
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
  final pages = [
    await document.appendBlankPage(),
    await document.appendBlankPage()
  ];
  PdfDictionary node(String title, PdfPage page) => PdfDictionary()
    ..attachToDocument(document)
    ..put(PdfName('Title'), PdfString(title))
    ..put(PdfName('Dest'),
        PdfArray.fromList([page.pdfRepresentation(), PdfName('Fit')]));
  final root = PdfDictionary()
    ..attachToDocument(document)
    ..put(PdfName.type, PdfName('Outlines'));
  final first = node('Alpha', pages[0]);
  final last = node('Beta', pages[1]);
  final child = node('Detail', pages[1]);
  root
    ..put(PdfName('First'), first)
    ..put(PdfName('Last'), last)
    ..put(PdfName('Count'), PdfNumber.fromInt(2));
  first
    ..put(PdfName.parent, root)
    ..put(PdfName('Next'), last)
    ..put(PdfName('First'), child)
    ..put(PdfName('Last'), child)
    ..put(PdfName('Count'), PdfNumber.fromInt(-1))
    ..put(PdfName('C'), PdfArray.fromDoubles([0.2, 0.4, 0.6]))
    ..put(PdfName('F'), PdfNumber.fromInt(2));
  last
    ..put(PdfName.parent, root)
    ..put(PdfName('Prev'), first);
  child.put(PdfName.parent, first);
  mutate?.call([first, last, child]);
  document.rootCatalog().pdfRepresentation().put(PdfName('Outlines'), root);
  await document.close();
  return bytes.takeBytes();
}

Future<PdfDocument> assemble(List<PdfPageSelection> sources) async =>
    PdfDocument.open(PdfReader.fromBytes(
        await PdfPageAssembly.merge(sources, preserveOutlines: true)));
Future<PdfDictionary> outlineRoot(PdfDocument document) async => (await document
    .rootCatalog()
    .pdfRepresentation()
    .dictionaryEntry(PdfName('Outlines')))!;
Future<PdfDictionary> target(PdfDictionary node) async =>
    (await (await node.arrayEntry(PdfName('Dest')))!.dictionaryEntry(0))!;

void main() {
  test('Outline opt-in preserves hierarchy, titles, styles and closed state',
      () async {
    final bytes = await outlineSource();
    await expectLater(PdfPageAssembly.merge([PdfPageSelection(bytes)]),
        throwsUnsupportedError);
    final result = await assemble([PdfPageSelection(bytes)]);
    addTearDown(result.close);
    final root = await outlineRoot(result);
    final first = (await root.dictionaryEntry(PdfName('First')))!;
    final child = (await first.dictionaryEntry(PdfName('First')))!;
    expect((await first.stringEntry(PdfName('Title')))!.getValue(), 'Alpha');
    expect((await child.stringEntry(PdfName('Title')))!.getValue(), 'Detail');
    expect(
        identical(await child.dictionaryEntry(PdfName.parent), first), isTrue);
    expect((await first.numberEntry(PdfName('Count')))!.intValue(), -1);
    expect((await root.numberEntry(PdfName('Count')))!.intValue(), 2);
    expect((await first.numberEntry(PdfName('F')))!.intValue(), 2);
    expect((await first.arrayEntry(PdfName('C')))!.size(), 3);
  });
  test('Reordered pages retarget explicit destinations', () async {
    final result = await assemble([
      PdfPageSelection(await outlineSource(), pages: [2, 1])
    ]);
    addTearDown(result.close);
    final first =
        (await (await outlineRoot(result)).dictionaryEntry(PdfName('First')))!;
    final last = (await first.dictionaryEntry(PdfName('Next')))!;
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
    var current =
        (await (await outlineRoot(result)).dictionaryEntry(PdfName('First')))!;
    for (var index = 1; index <= 4; index++) {
      expect(
          identical(await target(current),
              (await result.pageAt(index))!.pdfRepresentation()),
          isTrue);
      if (index < 4) {
        current = (await current.dictionaryEntry(PdfName('Next')))!;
      }
    }
  });
  test('Repeated page selection targets first copy and omitted targets reject',
      () async {
    final bytes = await outlineSource();
    final result = await assemble([
      PdfPageSelection(bytes, pages: [1, 1, 2])
    ]);
    addTearDown(result.close);
    final first =
        (await (await outlineRoot(result)).dictionaryEntry(PdfName('First')))!;
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
      final destination = nodes.first.remove(PdfName('Dest'));
      nodes.first.put(
          PdfName('A'),
          PdfDictionary()
            ..put(PdfName('S'), PdfName('GoTo'))
            ..put(PdfName('D'), destination!));
    });
    final result = await assemble([PdfPageSelection(bytes)]);
    addTearDown(result.close);
    final first =
        (await (await outlineRoot(result)).dictionaryEntry(PdfName('First')))!;
    expect(
        identical(
            await target(first), (await result.pageAt(1))!.pdfRepresentation()),
        isTrue);
  });
  test('Named destinations and cyclic outline siblings reject explicitly',
      () async {
    final named = await outlineSource(
        mutate: (nodes) =>
            nodes.first.put(PdfName('Dest'), PdfString('named')));
    await expectLater(
        assemble([PdfPageSelection(named)]), throwsUnsupportedError);
    final cycle = await outlineSource(
        mutate: (nodes) => nodes.first.put(PdfName('Next'), nodes.first));
    await expectLater(
        assemble([PdfPageSelection(cycle)]), throwsFormatException);
  });
}
