import 'dart:convert';
import 'dart:typed_data';
import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/kernel/pdf/writer_properties.dart';
import 'package:test/test.dart';

// Round-trip requirements adapted from loaded_document_round_trip_test.dart.
void main() {
  for (final compressed in [false, true]) {
    test(
        'new trailer entries and late streams survive Prev, compressed=$compressed',
        () async {
      final initial = BytesBuilder();
      final original = CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(
          initial,
          properties:
              CraftWriterProperties().setFullCompressionMode(compressed)));
      await _text(await original.appendBlankPage(), 'BASE');
      (await original.documentDetails()).pdfRepresentation().clear();
      await original.close();
      final bytes = BytesBuilder();
      final document = await _open(initial.takeBytes(), bytes, true);
      final overlay = await PdfPageOverlay.create((await document.pageAt(1))!);
      overlay.beginText();
      await overlay.setFontAndSize(
          CraftPdfFontFactory.createFont('Helvetica'), 12);
      overlay.moveText(40, 60).showText('ADDED').endText();
      (await document.documentDetails()).setTitle('Created in latest trailer');
      await document.close();
      final reopened = await CraftPdfDocument.open(
          CraftPdfReader.fromBytes(bytes.takeBytes()));
      try {
        expect(
            (await (await reopened.documentDetails())
                    .pdfRepresentation()
                    .stringEntry(CraftPdfName.title))
                ?.decodeMappingText(),
            'Created in latest trailer');
        final text =
            await PdfTextExtraction.fromPage((await reopened.pageAt(1))!);
        expect(text, contains('BASE'));
        expect(text, contains('ADDED'));
      } finally {
        await reopened.close();
      }
    });
  }
  for (final existing in [false, true]) {
    test('XMP enters the incremental object list, existing=$existing',
        () async {
      var source = await _source();
      if (existing) {
        final initial = BytesBuilder();
        final document = await _open(source, initial, false);
        await document.assignMetadataPayload(
            Uint8List.fromList(utf8.encode('<metadata>before</metadata>')));
        await document.close();
        source = initial.takeBytes();
      }
      final output = BytesBuilder();
      final document = await _open(source, output, true);
      await document.assignMetadataPayload(
          Uint8List.fromList(utf8.encode('<metadata>after</metadata>')));
      await document.close();
      final reopened = await CraftPdfDocument.open(
          CraftPdfReader.fromBytes(output.takeBytes()));
      try {
        expect(utf8.decode((await reopened.metadataPayload())!),
            contains('after'));
      } finally {
        await reopened.close();
      }
    });
  }
  for (final incremental in [false, true]) {
    test('insert/remove/rotate loaded pages, incremental=$incremental',
        () async {
      final source = await _source();
      final bytes = BytesBuilder();
      final document = await _open(source, bytes, incremental);
      final inserted = await document.insertBlankPage(2);
      await _text(inserted, 'INSERTED');
      await document.deletePageAt(3);
      (await document.pageAt(1))!.setRotationDegrees(90);
      await document.close();
      final resultBytes = bytes.takeBytes();
      if (incremental) expect(resultBytes.sublist(0, source.length), source);
      final result =
          await CraftPdfDocument.open(CraftPdfReader.fromBytes(resultBytes));
      try {
        expect(result.pageTotal(), 3);
        final texts = <String>[];
        for (var page = 1; page <= 3; page++) {
          texts.add(
              await PdfTextExtraction.fromPage((await result.pageAt(page))!));
        }
        expect(texts, ['Page 1', 'INSERTED', 'Page 3']);
        expect(await (await result.pageAt(1))!.rotationDegrees(), 90);
        expect(await (await result.pageAt(2))!.rotationDegrees(), 0);
      } finally {
        await result.close();
      }
    });
    test('metadata edits survive reopening, incremental=$incremental',
        () async {
      final bytes = BytesBuilder();
      final document = await _open(await _source(), bytes, incremental);
      final info = await document.documentDetails();
      info.setTitle('Updated title');
      info.setAuthor('Autor José 世界');
      info.setSubject('Updated subject');
      info.setKeywords('compatibility');
      info.setCreator('Caller');
      await document.close();
      final reopened = await CraftPdfDocument.open(
          CraftPdfReader.fromBytes(bytes.takeBytes()));
      try {
        final info = (await reopened.documentDetails()).pdfRepresentation();
        for (final entry in {
          'Title': 'Updated title',
          'Author': 'Autor José 世界',
          'Subject': 'Updated subject',
          'Keywords': 'compatibility',
          'Creator': 'Caller'
        }.entries) {
          expect(
              (await info.stringEntry(CraftPdfName(entry.key)))
                  ?.decodeMappingText(),
              entry.value);
        }
      } finally {
        await reopened.close();
      }
    });
  }
}

Future<CraftPdfDocument> _open(
    Uint8List source, BytesBuilder output, bool incremental) async {
  final document = CraftPdfDocument(
      reader: CraftPdfReader.fromBytes(source),
      writer: CraftPdfWriter.fromBytesBuilder(output),
      properties:
          incremental ? CraftStampingProperties().useAppendMode() : null);
  await document.load();
  return document;
}

Future<void> _text(CraftPdfPage page, String text) async {
  final canvas = await CraftPdfCanvas.fromPage(page);
  canvas.beginText();
  await canvas.setFontAndSize(CraftPdfFontFactory.createFont('Helvetica'), 18);
  canvas.moveText(40, 100).showText(text).endText();
}

Future<Uint8List> _source() async {
  final bytes = BytesBuilder();
  final doc = CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(bytes));
  for (var index = 1; index <= 3; index++) {
    await _text(await doc.appendBlankPage(), 'Page $index');
  }
  (await doc.documentDetails()).setTitle('Before');
  await doc.close();
  return bytes.takeBytes();
}
