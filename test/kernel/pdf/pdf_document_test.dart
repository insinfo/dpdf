import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:itext/src/kernel/pdf/pdf_document.dart';
import 'package:itext/src/kernel/pdf/pdf_writer.dart';
import 'package:itext/src/kernel/pdf/pdf_reader.dart';
import 'package:itext/src/kernel/geom/page_size.dart';

void main() {
  group('PdfDocument Tests', () {
    late String outPath;

    setUp(() {
      final outDir = Directory('test/out');
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
      outPath = 'test/out/simple_document.pdf';
    });

    test('Create simple PDF with one page', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      await pdfDoc.addNewPage(PageSize.A4);

      expect(pdfDoc.getNumberOfPages(), 1);

      await pdfDoc.close();

      final file = File(outPath);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(0));

      // Basic check of content
      final bytes = file.readAsBytesSync();
      final content = latin1.decode(bytes);
      expect(content, contains('%PDF-1.7'));
      expect(content, contains('%%EOF'));
      expect(content, contains('xref'));
      expect(content, contains('trailer'));
    });

    test('Read created PDF', () async {
      // Ensure the file exists
      final writer = PdfWriter.toFile(outPath);
      final pdfDocCreate = await PdfDocument.create(writer);
      await pdfDocCreate.addNewPage(PageSize.A4);
      await pdfDocCreate.close();

      final reader = await PdfReader.fromFile(outPath);
      final pdfDoc = await PdfDocument.open(reader);

      expect(pdfDoc.getNumberOfPages(), 1);
      await pdfDoc.close();
    });
  });
}
