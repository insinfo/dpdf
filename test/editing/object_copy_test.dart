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

Future<PdfDocument> create(BytesBuilder b) async =>
    PdfDocument.create(PdfWriter.fromBytesBuilder(b));
void main() {
  test('Object copy preserves cycles and shared identity through serialization',
      () async {
    final root = PdfDictionary();
    final shared = PdfDictionary()..put(PdfName('Owner'), root);
    root.put(PdfName('Left'), shared);
    root.put(PdfName('Right'), shared);
    final buffer = BytesBuilder();
    final output = await create(buffer);
    await output.appendBlankPage();
    final copied = await root.copyTo(output) as PdfDictionary;
    expect(await copied.dictionaryEntry(PdfName('Left')),
        same(await copied.dictionaryEntry(PdfName('Right'))));
    output.rootCatalog().pdfRepresentation().put(PdfName('Graph'), copied);
    await output.close();
    final reopened =
        await PdfDocument.open(PdfReader.fromBytes(buffer.takeBytes()));
    final graph = (await reopened
        .rootCatalog()
        .pdfRepresentation()
        .dictionaryEntry(PdfName('Graph')))!;
    final left = (await graph.dictionaryEntry(PdfName('Left')))!;
    expect(await left.dictionaryEntry(PdfName('Owner')), same(graph));
    expect(await graph.dictionaryEntry(PdfName('Right')), same(left));
    await reopened.close();
  });
  test('Original copyPagesTo maps links and shared resources across documents',
      () async {
    final sourceBuffer = BytesBuilder();
    final source = await create(sourceBuffer);
    final first = await source.appendBlankPage();
    final second = await source.appendBlankPage();
    final resources = PdfDictionary();
    resources.attachToDocument(source);
    for (final page in [first, second]) {
      page.pdfRepresentation().put(PdfName.resources, resources);
      page.pdfRepresentation().put(PdfName.contents,
          PdfStream.withBytes(Uint8List.fromList(ascii.encode('q Q')), 0));
    }
    final annotation = PdfDictionary()
      ..put(PdfName.type, PdfName('Annot'))
      ..put(PdfName.subtype, PdfName('Link'))
      ..put(PdfName('P'), first.pdfRepresentation())
      ..put(PdfName('Dest'),
          PdfArray.fromList([second.pdfRepresentation(), PdfName('Fit')]));
    first
        .pdfRepresentation()
        .put(PdfName.annots, PdfArray.fromList([annotation]));
    final outBuffer = BytesBuilder();
    final output = await create(outBuffer);
    final copied = await source.transferPagesInto([1, 2], output);
    expect(copied.length, 2);
    expect(
        await copied[0].pdfRepresentation().dictionaryEntry(PdfName.resources),
        same(await copied[1]
            .pdfRepresentation()
            .dictionaryEntry(PdfName.resources)));
    await output.close();
    await source.close();
    final reopened =
        await PdfDocument.open(PdfReader.fromBytes(outBuffer.takeBytes()));
    final page1 = (await reopened.pageAt(1))!.pdfRepresentation();
    final page2 = (await reopened.pageAt(2))!.pdfRepresentation();
    final annots = (await page1.arrayEntry(PdfName.annots))!;
    final annot = await annots.get(0) as PdfDictionary;
    expect(await annot.dictionaryEntry(PdfName('P')), same(page1));
    expect(
        await (await annot.arrayEntry(PdfName('Dest')))!.get(0), same(page2));
    await reopened.close();
  });
  test('Unselected page links fail without publishing partial objects',
      () async {
    final source = await create(BytesBuilder());
    final first = await source.appendBlankPage();
    final second = await source.appendBlankPage();
    first.pdfRepresentation().put(PdfName('Peer'), second.pdfRepresentation());
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
