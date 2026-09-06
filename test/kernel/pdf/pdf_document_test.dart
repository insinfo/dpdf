import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_page.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/geom/page_size.dart';

void main() {
  group('PdfDocument Tests', () {
    late String outPath;

    setUp(() {
      final outDir = Directory('test/tmp');
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
      outPath = 'test/tmp/pdf_document_test.pdf';
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
      // Create a file first
      final writer = PdfWriter.toFile(outPath);
      final pdfDocCreate = await PdfDocument.create(writer);
      await pdfDocCreate.addNewPage(PageSize.A4);
      await pdfDocCreate.close();

      final reader = await PdfReader.fromFile(outPath);
      final pdfDoc = await PdfDocument.open(reader);

      expect(pdfDoc.getNumberOfPages(), 1);
      await pdfDoc.close();
    });

    test('getFirstPage and getLastPage', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      // Add 3 pages
      await pdfDoc.addNewPage(PageSize.A4);
      await pdfDoc.addNewPage(PageSize.A4);
      await pdfDoc.addNewPage(PageSize.A4);

      expect(pdfDoc.getNumberOfPages(), 3);

      final firstPage = await pdfDoc.getFirstPage();
      final lastPage = await pdfDoc.getLastPage();

      expect(firstPage, isNotNull);
      expect(lastPage, isNotNull);
      expect(pdfDoc.getPageNumber(firstPage!), 1);
      expect(pdfDoc.getPageNumber(lastPage!), 3);

      await pdfDoc.close();
    });

    test('getDefaultFont returns a font', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      final font = pdfDoc.getDefaultFont();
      expect(font, isNotNull);

      await pdfDoc.addNewPage();
      await pdfDoc.close();
    });

    test('getNumberOfPdfObjects', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      // Initially should have at least 1 object (catalog)
      expect(pdfDoc.getNumberOfPdfObjects(), greaterThan(0));

      await pdfDoc.addNewPage();

      // After adding a page should have more objects
      expect(pdfDoc.getNumberOfPdfObjects(), greaterThan(1));

      await pdfDoc.close();
    });

    test('isEncrypted returns false for unencrypted document', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      expect(pdfDoc.isEncrypted(), false);

      await pdfDoc.addNewPage();
      await pdfDoc.close();
    });

    test('isClosed and isClosing', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      expect(pdfDoc.isClosed(), false);
      expect(pdfDoc.isClosing(), false);

      await pdfDoc.addNewPage();
      await pdfDoc.close();

      expect(pdfDoc.isClosed(), true);
    });

    test('getCatalog returns valid catalog', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      final catalog = pdfDoc.getCatalog();
      expect(catalog, isNotNull);
      expect(catalog.getPdfObject(), isNotNull);

      await pdfDoc.addNewPage();
      await pdfDoc.close();
    });

    test('getTrailer returns valid trailer', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      final trailer = pdfDoc.getTrailer();
      expect(trailer, isNotNull);

      await pdfDoc.addNewPage();
      await pdfDoc.close();
    });

    test('getVersion returns correct version', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      final version = pdfDoc.getVersion();
      expect(version, isNotNull);

      await pdfDoc.addNewPage();
      await pdfDoc.close();
    });

    test('setDefaultPageSize affects new pages', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      pdfDoc.setDefaultPageSize(PageSize.letter);
      expect(pdfDoc.getDefaultPageSize(), PageSize.letter);

      await pdfDoc.addNewPage(); // Should use letter size

      await pdfDoc.close();
    });

    test('Multiple pages with different sizes', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      await pdfDoc.addNewPage(PageSize.A4);
      await pdfDoc.addNewPage(PageSize.letter);
      await pdfDoc.addNewPage(PageSize.A5);

      expect(pdfDoc.getNumberOfPages(), 3);

      await pdfDoc.close();

      // Verify by reading
      final reader = await PdfReader.fromFile(outPath);
      final pdfDocRead = await PdfDocument.open(reader);
      expect(pdfDocRead.getNumberOfPages(), 3);
      await pdfDocRead.close();
    });

    test('removePage removes a page from the document', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      // Add 3 pages
      await pdfDoc.addNewPage(PageSize.A4);
      await pdfDoc.addNewPage(PageSize.A4);
      await pdfDoc.addNewPage(PageSize.A4);

      expect(pdfDoc.getNumberOfPages(), 3);

      // Remove the middle page
      await pdfDoc.removePageAt(2);

      expect(pdfDoc.getNumberOfPages(), 2);

      await pdfDoc.close();

      // Verify the file was created
      final file = File(outPath);
      expect(file.existsSync(), true);
    });

    test('getPdfObject returns objects by number', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      await pdfDoc.addNewPage(PageSize.A4);

      // Object 1 should be the catalog
      final obj1 = await pdfDoc.getPdfObject(1);
      expect(obj1, isNotNull);

      await pdfDoc.close();
    });

    test('addNewPageAt inserts page at specific position', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      // Add pages at the end
      await pdfDoc.addNewPage(PageSize.A4); // Page 1
      await pdfDoc.addNewPage(PageSize.A4); // Page 2
      await pdfDoc.addNewPage(PageSize.A4); // Page 3

      expect(pdfDoc.getNumberOfPages(), 3);

      // Insert a new page at position 2 (becomes new page 2)
      await pdfDoc.addNewPageAt(2, PageSize.letter);

      expect(pdfDoc.getNumberOfPages(), 4);

      await pdfDoc.close();

      // Verify the file was created
      final file = File(outPath);
      expect(file.existsSync(), true);
    });

    test('addPage adds existing page to document', () async {
      final writer = PdfWriter.toFile(outPath);
      final pdfDoc = await PdfDocument.create(writer);

      final page = PdfPage(PdfDictionary());
      page.setMediaBox(PageSize.A4);

      await pdfDoc.addPage(page);

      expect(pdfDoc.getNumberOfPages(), 1);

      await pdfDoc.close();
    });
  });
}
