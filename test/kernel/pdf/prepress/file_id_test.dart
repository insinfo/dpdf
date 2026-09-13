import 'dart:typed_data';

import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/stamping_properties.dart';
import 'package:dpdf/src/kernel/pdf/writer_properties.dart';
import 'package:test/test.dart';

/// The two byte strings of the trailer `/ID` array, as hexadecimal.
Future<List<String>> fileIdentifiers(Uint8List bytes) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  final array = await document.fileTrailer().arrayEntry(PdfName.id);
  expect(array, isNotNull,
      reason: '/ID should be present in the trailer (14.4)');
  final result = <String>[];
  for (var i = 0; i < array!.size(); i++) {
    final entry = await array.stringEntry(i);
    expect(entry, isNotNull, reason: '/ID entry $i shall be a byte string');
    result.add(entry!
        .getValueBytes()!
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join());
  }
  await document.close();
  return result;
}

/// Writes a one page document and returns its bytes.
Future<Uint8List> createDocument({WriterProperties? properties}) async {
  final bytes = BytesBuilder();
  final document = PdfDocument.create(
      PdfWriter.fromBytesBuilder(bytes, properties: properties));
  await document.appendBlankPage(PageSize.A4);
  await document.close();
  return bytes.toBytes();
}

/// Reopens [source] with a writer and adds a page.
Future<Uint8List> updateDocument(Uint8List source,
    {bool incremental = false, WriterProperties? properties}) async {
  final bytes = BytesBuilder();
  final document = PdfDocument(
      reader: PdfReader.fromBytes(source),
      writer: PdfWriter.fromBytesBuilder(bytes, properties: properties),
      properties: incremental ? (StampingProperties()..useAppendMode()) : null);
  await document.load();
  await document.appendBlankPage(PageSize.A4);
  await document.close();
  return bytes.toBytes();
}

void main() {
  group('File identifiers, ISO 32000-1 14.4', () {
    test('/ID holds exactly two byte strings', () async {
      final identifiers = await fileIdentifiers(await createDocument());
      expect(identifiers.length, 2);
      expect(identifiers[0], isNotEmpty);
      expect(identifiers[1], isNotEmpty);
    });

    test('both identifiers are equal when a file is first written', () async {
      final identifiers = await fileIdentifiers(await createDocument());
      expect(identifiers[0], identifiers[1]);
    });

    test('two documents written separately get different identifiers',
        () async {
      final first = await fileIdentifiers(await createDocument());
      final second = await fileIdentifiers(await createDocument());
      expect(first[0], isNot(second[0]));
    });

    test('an incremental update keeps the first and changes the second',
        () async {
      final original = await createDocument();
      final before = await fileIdentifiers(original);
      final after = await fileIdentifiers(
          await updateDocument(original, incremental: true));

      expect(after[0], before[0],
          reason: 'the permanent identifier shall not change on an update');
      expect(after[1], isNot(before[1]),
          reason: 'the changing identifier shall be renewed on every update');
    });

    test('a full rewrite keeps the first and changes the second', () async {
      final original = await createDocument();
      final before = await fileIdentifiers(original);
      final after = await fileIdentifiers(await updateDocument(original));

      expect(after[0], before[0]);
      expect(after[1], isNot(before[1]));
    });

    test('two successive updates each renew the changing identifier', () async {
      final original = await createDocument();
      final once = await updateDocument(original, incremental: true);
      final twice = await updateDocument(once, incremental: true);

      final a = await fileIdentifiers(original);
      final b = await fileIdentifiers(once);
      final c = await fileIdentifiers(twice);

      expect(b[0], a[0]);
      expect(c[0], a[0]);
      expect({a[1], b[1], c[1]}.length, 3);
    });

    test('reading a document without writing leaves /ID untouched', () async {
      final original = await createDocument();
      final before = await fileIdentifiers(original);

      final document = await PdfDocument.open(PdfReader.fromBytes(original));
      expect(
          document
              .initialDocumentIdentifier()
              .getValueBytes()!
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(),
          before[0]);
      expect(
          document
              .revisionIdentifier()
              .getValueBytes()!
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(),
          before[1]);
      await document.close();
    });

    test('the writer properties can pin both identifiers', () async {
      final properties = WriterProperties()
        ..setInitialDocumentId('0123456789abcdef')
        ..setModifiedDocumentId('fedcba9876543210');
      final identifiers =
          await fileIdentifiers(await createDocument(properties: properties));

      expect(
          String.fromCharCodes(List<int>.generate(
              identifiers[0].length ~/ 2,
              (i) => int.parse(identifiers[0].substring(i * 2, i * 2 + 2),
                  radix: 16))),
          '0123456789abcdef');
      expect(
          String.fromCharCodes(List<int>.generate(
              identifiers[1].length ~/ 2,
              (i) => int.parse(identifiers[1].substring(i * 2, i * 2 + 2),
                  radix: 16))),
          'fedcba9876543210');
    });

    test('a pinned modified identifier wins over the renewal on an update',
        () async {
      final original = await createDocument();
      final before = await fileIdentifiers(original);
      final updated = await updateDocument(original,
          incremental: true,
          properties: WriterProperties()..setModifiedDocumentId('fixed'));
      final after = await fileIdentifiers(updated);

      expect(after[0], before[0]);
      expect(after[1], '6669786564');
    });
  });
}
