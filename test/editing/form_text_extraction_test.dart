import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';

PdfStream stream(String text) =>
    PdfStream.withBytes(Uint8List.fromList(ascii.encode(text)), 0);
PdfStream form(String text, [PdfDictionary? resources]) {
  final result = stream(text)..put(PdfName.subtype, PdfName('Form'));
  if (resources != null) result.put(PdfName.resources, resources);
  return result;
}

PdfDictionary resources(Map<String, PdfStream> forms,
        {String font = 'Helvetica'}) =>
    PdfDictionary()
      ..put(
          PdfName.font,
          PdfDictionary()
            ..put(
                PdfName('F1'),
                PdfDictionary()
                  ..put(PdfName.subtype, PdfName('Type1'))
                  ..put(PdfName.baseFont, PdfName(font))))
      ..put(
          PdfName('XObject'),
          PdfDictionary.fromEntries(
              forms.entries.map((e) => MapEntry(PdfName(e.key), e.value))));
Future<String> extract(String content, PdfDictionary directory) async {
  final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(BytesBuilder()));
  final page = await doc.appendBlankPage();
  page.pdfRepresentation()
    ..put(PdfName.resources, directory)
    ..put(PdfName.contents, stream(content));
  // Do not serialize deliberately cyclic fixtures.
  return PdfTextExtraction.fromPage(page);
}

void main() {
  test('Shared indirect Form survives write and reopen', () async {
    final bytes = BytesBuilder();
    final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
    final page = await doc.appendBlankPage();
    page.pdfRepresentation()
      ..put(PdfName.resources,
          resources({'X': form('BT /F1 12 Tf (shared) Tj ET')}))
      ..put(PdfName.contents, stream('/X Do /X Do'));
    await doc.close();
    final reopened =
        await PdfDocument.open(PdfReader.fromBytes(bytes.takeBytes()));
    try {
      expect(await PdfTextExtraction.fromPage((await reopened.pageAt(1))!),
          'sharedshared');
    } finally {
      await reopened.close();
    }
  });

  test('Visits repeated Form occurrences between page text', () async {
    final child = form('BT /F1 12 Tf (form) Tj ET');
    expect(
        await extract(
            'BT /F1 12 Tf (before) Tj ET /X Do /X Do BT (after) Tj ET',
            resources({'X': child})),
        'beforeformformafter');
  });
  test('Nested Forms use their own resource directory', () async {
    final inner = form('BT /F1 12 Tf (inner) Tj ET');
    final outer = form('/Inner Do', resources({'Inner': inner}));
    expect(await extract('/Outer Do', resources({'Outer': outer})), 'inner');
  });
  test('A Form without Resources inherits caller resources and selected font',
      () async {
    final child = form('BT (inherited) Tj ET');
    expect(await extract('BT /F1 12 Tf ET /X Do', resources({'X': child})),
        'inherited');
  });
  test(
      'Inherited selected font retains decoder despite local font name collision',
      () async {
    final child =
        form('BT (inherited) Tj ET', resources({}, font: 'UnknownTypeface'));
    expect(await extract('BT /F1 12 Tf ET /X Do', resources({'X': child})),
        'inherited');
  });
  test(
      'Selecting a local font does not fall back to a caller font with same name',
      () async {
    final child = form('BT /F1 12 Tf (unsupported) Tj ET',
        resources({}, font: 'UnknownTypeface'));
    await expectLater(
        extract('/X Do', resources({'X': child})), throwsUnsupportedError);
  });
  test('Recursive Form reports malformed graph', () async {
    final child = form('/X Do');
    await expectLater(
        extract('/X Do', resources({'X': child})), throwsFormatException);
  });
  test('Missing XObject reports malformed content', () async {
    await expectLater(
        extract('/Missing Do', resources({})), throwsFormatException);
  });
  test('Raw content retains explicit rejection without resource context', () {
    expect(
        () => PdfTextExtraction.fromContent(
            Uint8List.fromList(ascii.encode('/X Do')),
            decoder: (_, bytes) => ascii.decode(bytes)),
        throwsUnsupportedError);
  });
}
