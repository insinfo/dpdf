import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';

import 'package:dpdf/src/kernel/geom/page_size.dart';

void main() {
  group('PDF Pages Creation Tests', () {
    test('Create PDF with one page and verify count', () async {
      // Create a simple PDF with 1 page
      final outputBuffer = BytesBuilder();
      final tempSink = _BytesBuilderSink(outputBuffer);
      final doc = PdfDocument(writer: PdfWriter(tempSink));

      // Add one page
      await doc.addNewPage(PageSize.A4);
      expect(doc.getPagesTree().getNumberOfPages(), equals(1));

      // Close and get bytes
      await doc.close();
      final pdfBytes = outputBuffer.toBytes();
      expect(pdfBytes.length, greaterThan(0));

      // Re-read and verify
      final reader = PdfReader.fromBytes(pdfBytes);
      final doc2 = PdfDocument(reader: reader);
      await doc2.load();

      expect(doc2.getPagesTree().getNumberOfPages(), equals(1));
    });

    test('Create PDF with multiple pages and verify count', () async {
      // Create a PDF with 5 pages
      final outputBuffer = BytesBuilder();
      final tempSink = _BytesBuilderSink(outputBuffer);
      final doc = PdfDocument(writer: PdfWriter(tempSink));

      // Add 5 pages
      for (var i = 0; i < 5; i++) {
        await doc.addNewPage(PageSize.A4);
      }
      expect(doc.getPagesTree().getNumberOfPages(), equals(5));

      // Close and get bytes
      await doc.close();
      final pdfBytes = outputBuffer.toBytes();

      // Re-read and verify
      final reader = PdfReader.fromBytes(pdfBytes);
      final doc2 = PdfDocument(reader: reader);
      await doc2.load();

      expect(doc2.getPagesTree().getNumberOfPages(), equals(5));

      // Verify each page can be accessed
      for (var i = 1; i <= 5; i++) {
        final page = await doc2.getPage(i);
        expect(page, isNotNull, reason: 'Page $i should not be null');
      }
    });

    test('PDF structure is valid and contains Pages with Count', () async {
      // Create a simple PDF
      final outputBuffer = BytesBuilder();
      final tempSink = _BytesBuilderSink(outputBuffer);
      final doc = PdfDocument(writer: PdfWriter(tempSink));
      await doc.addNewPage(PageSize.A4);
      await doc.addNewPage(PageSize.A4);
      await doc.close();

      final pdfBytes = outputBuffer.toBytes();
      final pdfString = String.fromCharCodes(pdfBytes);

      // Verify PDF has expected structure markers
      expect(pdfString.contains('%PDF-'), isTrue,
          reason: 'Should have PDF header');
      expect(pdfString.contains('/Pages'), isTrue,
          reason: 'Should have Pages entry');
      expect(pdfString.contains('/Count'), isTrue,
          reason: 'Should have Count entry');
      expect(pdfString.contains('/Page'), isTrue,
          reason: 'Should have Page type');
      expect(pdfString.contains('%%EOF'), isTrue,
          reason: 'Should have EOF marker');
    });
  });
}

/// Helper sink that writes to a BytesBuilder (same as in pdf_signer.dart)
class _BytesBuilderSink implements IOSink {
  final BytesBuilder _builder;

  _BytesBuilderSink(this._builder);

  @override
  void add(List<int> data) {
    _builder.add(data);
  }

  @override
  void write(Object? object) {
    if (object is List<int>) {
      _builder.add(object);
    } else {
      _builder.add(object.toString().codeUnits);
    }
  }

  @override
  Future close() async {}

  @override
  Future get done => Future.value();

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding value) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future flush() async {}

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    var first = true;
    for (final obj in objects) {
      if (!first) write(separator);
      write(obj);
      first = false;
    }
  }

  @override
  void writeCharCode(int charCode) {
    _builder.addByte(charCode);
  }

  @override
  void writeln([Object? object = '']) {
    write(object);
    write('\n');
  }
}
