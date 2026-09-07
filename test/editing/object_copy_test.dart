import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';

Future<CraftPdfDocument> create(BytesBuilder b) async =>
    CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(b));
void main() {
  test('Object copy preserves cycles and shared identity through serialization',
      () async {
    final root = CraftPdfDictionary();
    final shared = CraftPdfDictionary()..put(CraftPdfName('Owner'), root);
    root.put(CraftPdfName('Left'), shared);
    root.put(CraftPdfName('Right'), shared);
    final buffer = BytesBuilder();
    final output = await create(buffer);
    await output.appendBlankPage();
    final copied = await root.copyTo(output) as CraftPdfDictionary;
    expect(await copied.dictionaryEntry(CraftPdfName('Left')),
        same(await copied.dictionaryEntry(CraftPdfName('Right'))));
    output.rootCatalog().pdfRepresentation().put(CraftPdfName('Graph'), copied);
    await output.close();
    final reopened = await CraftPdfDocument.open(
        CraftPdfReader.fromBytes(buffer.takeBytes()));
    final graph = (await reopened
        .rootCatalog()
        .pdfRepresentation()
        .dictionaryEntry(CraftPdfName('Graph')))!;
    final left = (await graph.dictionaryEntry(CraftPdfName('Left')))!;
    expect(await left.dictionaryEntry(CraftPdfName('Owner')), same(graph));
    expect(await graph.dictionaryEntry(CraftPdfName('Right')), same(left));
    await reopened.close();
  });
  test('Original copyPagesTo maps links and shared resources across documents',
      () async {
    final sourceBuffer = BytesBuilder();
    final source = await create(sourceBuffer);
    final first = await source.appendBlankPage();
    final second = await source.appendBlankPage();
    final resources = CraftPdfDictionary();
    resources.attachToDocument(source);
    for (final page in [first, second]) {
      page.pdfRepresentation().put(CraftPdfName.resources, resources);
      page.pdfRepresentation().put(CraftPdfName.contents,
          CraftPdfStream.withBytes(Uint8List.fromList(ascii.encode('q Q')), 0));
    }
    final annotation = CraftPdfDictionary()
      ..put(CraftPdfName.type, CraftPdfName('Annot'))
      ..put(CraftPdfName.subtype, CraftPdfName('Link'))
      ..put(CraftPdfName('P'), first.pdfRepresentation())
      ..put(
          CraftPdfName('Dest'),
          CraftPdfArray.fromList(
              [second.pdfRepresentation(), CraftPdfName('Fit')]));
    first
        .pdfRepresentation()
        .put(CraftPdfName.annots, CraftPdfArray.fromList([annotation]));
    final outBuffer = BytesBuilder();
    final output = await create(outBuffer);
    final copied = await source.transferPagesInto([1, 2], output);
    expect(copied.length, 2);
    expect(
        await copied[0]
            .pdfRepresentation()
            .dictionaryEntry(CraftPdfName.resources),
        same(await copied[1]
            .pdfRepresentation()
            .dictionaryEntry(CraftPdfName.resources)));
    await output.close();
    await source.close();
    final reopened = await CraftPdfDocument.open(
        CraftPdfReader.fromBytes(outBuffer.takeBytes()));
    final page1 = (await reopened.pageAt(1))!.pdfRepresentation();
    final page2 = (await reopened.pageAt(2))!.pdfRepresentation();
    final annots = (await page1.arrayEntry(CraftPdfName.annots))!;
    final annot = await annots.get(0) as CraftPdfDictionary;
    expect(await annot.dictionaryEntry(CraftPdfName('P')), same(page1));
    expect(await (await annot.arrayEntry(CraftPdfName('Dest')))!.get(0),
        same(page2));
    await reopened.close();
  });
  test('Unselected page links fail without publishing partial objects',
      () async {
    final source = await create(BytesBuilder());
    final first = await source.appendBlankPage();
    final second = await source.appendBlankPage();
    first
        .pdfRepresentation()
        .put(CraftPdfName('Peer'), second.pdfRepresentation());
    final output = await create(BytesBuilder());
    final countBefore = output.crossReferenceTable().size();
    await expectLater(
        source.transferPagesInto([1], output), throwsUnsupportedError);
    expect(output.pageTotal(), 0);
    expect(output.crossReferenceTable().size(), countBefore);
    await source.close();
    await output.close();
  });
}
