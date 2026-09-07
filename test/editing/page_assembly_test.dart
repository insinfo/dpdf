import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:test/test.dart';
import 'package:dpdf/src/editing/pdf_page_assembly.dart';
import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';

Future<Uint8List> fixture(List<String> texts) async {
  final buffer = BytesBuilder();
  final doc = CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(buffer));
  for (final text in texts) {
    final page = await doc.appendBlankPage();
    page.pdfRepresentation().put(
        CraftPdfName.contents,
        CraftPdfStream.withBytes(
            Uint8List.fromList(ascii.encode('BT /F1 12 Tf ($text) Tj ET')), 0));
  }
  await doc.close();
  return buffer.takeBytes();
}

void main() {
  String extract(String stream) =>
      PdfTextExtraction.fromContent(Uint8List.fromList(latin1.encode(stream)),
          decoder: (_, bytes) => latin1.decode(bytes));
  test('Literal strings, escapes, octal, hex and TJ arrays', () {
    expect(extract(r'BT /F1 12 Tf (a\(b\)\040c) Tj [( d) -10 <2065>] TJ ET'),
        'a(b) c d e');
    expect(extract('BT /F1 12 Tf (a(b)c) Tj ET'), 'a(b)c');
    expect(extract('BT /F1 12 Tf <414> Tj ET'), 'A@');
  });
  test('Transforms preserve stream text order and quote operators', () {
    expect(
        extract(
            'q 0 1 -1 0 50 60 cm BT /F1 12 Tf 1 0 0 1 10 20 Tm (a) Tj (b) \' 1 2 (c) " ET Q'),
        'a\nb\nc');
  });
  test('Unsupported content and malformed state do not silently pass', () {
    for (final stream in ['BI', '/X Do', '/GS gs', 'bogus']) {
      expect(() => extract(stream), throwsUnsupportedError);
    }
    for (final stream in [
      '/Span BDC',
      'BT',
      'Q',
      'BT /F1 12 Tf (abc',
      'BT /F1 12 Tf [(x)'
    ]) {
      expect(() => extract(stream), throwsFormatException);
    }
  });
  test('Merge documents, reorder and duplicate pages; read output again',
      () async {
    final first = await fixture(['first', 'second']);
    final second = await fixture(['third']);
    final bytes = await PdfPageAssembly.merge([
      PdfPageSelection(first, pages: [2, 1, 2]),
      PdfPageSelection(second),
    ]);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    expect(doc.pageTotal(), 4);
    final texts = <String>[];
    for (var i = 1; i <= 4; i++) {
      texts.add(PdfTextExtraction.fromContent(
          await (await doc.pageAt(i))!.contentPayload(),
          decoder: (_, data) => ascii.decode(data)));
    }
    expect(texts, ['second', 'first', 'second', 'third']);
    await doc.close();
  });
  test('Invalid page selection fails', () async {
    expect(
        PdfPageAssembly.merge([
          PdfPageSelection(await fixture(['x']), pages: [2])
        ]),
        throwsRangeError);
  });
  test('Compressed streams and shared resources survive assembly', () async {
    final buffer = BytesBuilder();
    final source =
        CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(buffer));
    final resources = CraftPdfDictionary();
    final fonts = CraftPdfDictionary();
    final font = CraftPdfDictionary()
      ..put(CraftPdfName.type, CraftPdfName.font)
      ..put(CraftPdfName.subtype, CraftPdfName('Type1'))
      ..put(CraftPdfName.baseFont, CraftPdfName('Helvetica'));
    fonts.put(CraftPdfName('F1'), font);
    resources.put(CraftPdfName.font, fonts);
    resources.attachToDocument(source);
    for (var i = 0; i < 2; i++) {
      final page = await source.appendBlankPage();
      page.pdfRepresentation().put(CraftPdfName.resources, resources);
      final stream = CraftPdfStream.withBytes(
          Uint8List.fromList(
              zlib.encode(ascii.encode('BT /F1 10 Tf (shared-$i) Tj ET'))),
          0)
        ..put(CraftPdfName.filter, CraftPdfName('FlateDecode'));
      page.pdfRepresentation().put(CraftPdfName.contents, stream);
    }
    await source.close();
    final assembled =
        await PdfPageAssembly.merge([PdfPageSelection(buffer.takeBytes())]);
    final doc =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(assembled));
    final encoded = await (await doc.pageAt(1))!
        .pdfRepresentation()
        .streamEntry(CraftPdfName.contents);
    expect(ascii.decode(zlib.decode((await encoded!.getBytes(false))!)),
        'BT /F1 10 Tf (shared-0) Tj ET');
    expect(
        await PdfTextExtraction.fromPage((await doc.pageAt(1))!), 'shared-0');
    expect(
        await PdfTextExtraction.fromPage((await doc.pageAt(2))!), 'shared-1');
    await doc.close();
  });
  test('Interactive documents are rejected before returning output', () async {
    final buffer = BytesBuilder();
    final source =
        CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(buffer));
    await source.appendBlankPage();
    source
        .rootCatalog()
        .pdfRepresentation()
        .put(CraftPdfName('AcroForm'), CraftPdfDictionary());
    await source.close();
    expect(PdfPageAssembly.merge([PdfPageSelection(buffer.takeBytes())]),
        throwsUnsupportedError);
  });
  test('Corrupt compressed content fails instead of exposing undecoded text',
      () async {
    final buffer = BytesBuilder();
    final source =
        CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(buffer));
    final page = await source.appendBlankPage();
    page.pdfRepresentation().put(
        CraftPdfName.contents,
        CraftPdfStream.withBytes(
            Uint8List.fromList(ascii.encode('BT /F1 12 Tf (wrong) Tj ET')), 0)
          ..put(CraftPdfName.filter, CraftPdfName('FlateDecode')));
    expect(
        PdfTextExtraction.fromPage(page,
            decoder: (_, codes) => ascii.decode(codes)),
        throwsFormatException);
    await source.close();
  });
}
