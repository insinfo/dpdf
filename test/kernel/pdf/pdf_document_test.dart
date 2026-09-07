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
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      await pdfDoc.appendBlankPage(CraftPageSize.A4);

      expect(pdfDoc.pageTotal(), 1);

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
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDocCreate = CraftPdfDocument.create(writer);
      await pdfDocCreate.appendBlankPage(CraftPageSize.A4);
      await pdfDocCreate.close();

      final reader = await CraftPdfReader.fromFile(outPath);
      final pdfDoc = await CraftPdfDocument.open(reader);

      expect(pdfDoc.pageTotal(), 1);
      await pdfDoc.close();
    });

    test('getFirstPage and getLastPage', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      // Add 3 pages
      await pdfDoc.appendBlankPage(CraftPageSize.A4);
      await pdfDoc.appendBlankPage(CraftPageSize.A4);
      await pdfDoc.appendBlankPage(CraftPageSize.A4);

      expect(pdfDoc.pageTotal(), 3);

      final firstPage = await pdfDoc.firstPage();
      final lastPage = await pdfDoc.lastPage();

      expect(firstPage, isNotNull);
      expect(lastPage, isNotNull);
      expect(pdfDoc.pageOrdinal(firstPage!), 1);
      expect(pdfDoc.pageOrdinal(lastPage!), 3);

      await pdfDoc.close();
    });

    test('getDefaultFont returns a font', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      final font = pdfDoc.defaultTypeface();
      expect(font, isNotNull);

      await pdfDoc.appendBlankPage();
      await pdfDoc.close();
    });

    test('getNumberOfPdfObjects', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      // Initially should have at least 1 object (catalog)
      expect(pdfDoc.storedObjectCount(), greaterThan(0));

      await pdfDoc.appendBlankPage();

      // After adding a page should have more objects
      expect(pdfDoc.storedObjectCount(), greaterThan(1));

      await pdfDoc.close();
    });

    test('isEncrypted returns false for unencrypted document', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      expect(pdfDoc.usesEncryption(), false);

      await pdfDoc.appendBlankPage();
      await pdfDoc.close();
    });

    test('isClosed and isClosing', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      expect(pdfDoc.lifecycleClosed(), false);
      expect(pdfDoc.lifecycleClosing(), false);

      await pdfDoc.appendBlankPage();
      await pdfDoc.close();

      expect(pdfDoc.lifecycleClosed(), true);
    });

    test('getCatalog returns valid catalog', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      final catalog = pdfDoc.rootCatalog();
      expect(catalog, isNotNull);
      expect(catalog.pdfRepresentation(), isNotNull);

      await pdfDoc.appendBlankPage();
      await pdfDoc.close();
    });

    test('getTrailer returns valid trailer', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      final trailer = pdfDoc.fileTrailer();
      expect(trailer, isNotNull);

      await pdfDoc.appendBlankPage();
      await pdfDoc.close();
    });

    test('getVersion returns correct version', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      final version = pdfDoc.formatVersion();
      expect(version, isNotNull);

      await pdfDoc.appendBlankPage();
      await pdfDoc.close();
    });

    test('setDefaultPageSize affects new pages', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      pdfDoc.configureDefaultPageExtent(CraftPageSize.letter);
      expect(pdfDoc.defaultPageExtent(), CraftPageSize.letter);

      await pdfDoc.appendBlankPage(); // Should use letter size

      await pdfDoc.close();
    });

    test('Multiple pages with different sizes', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      await pdfDoc.appendBlankPage(CraftPageSize.A4);
      await pdfDoc.appendBlankPage(CraftPageSize.letter);
      await pdfDoc.appendBlankPage(CraftPageSize.A5);

      expect(pdfDoc.pageTotal(), 3);

      await pdfDoc.close();

      // Verify by reading
      final reader = await CraftPdfReader.fromFile(outPath);
      final pdfDocRead = await CraftPdfDocument.open(reader);
      expect(pdfDocRead.pageTotal(), 3);
      await pdfDocRead.close();
    });

    test('removePage removes a page from the document', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      // Add 3 pages
      await pdfDoc.appendBlankPage(CraftPageSize.A4);
      await pdfDoc.appendBlankPage(CraftPageSize.A4);
      await pdfDoc.appendBlankPage(CraftPageSize.A4);

      expect(pdfDoc.pageTotal(), 3);

      // Remove the middle page
      await pdfDoc.deletePageAt(2);

      expect(pdfDoc.pageTotal(), 2);

      await pdfDoc.close();

      // Verify the file was created
      final file = File(outPath);
      expect(file.existsSync(), true);
    });

    test('getPdfObject returns objects by number', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      await pdfDoc.appendBlankPage(CraftPageSize.A4);

      // Object 1 should be the catalog
      final obj1 = await pdfDoc.pdfRepresentation(1);
      expect(obj1, isNotNull);

      await pdfDoc.close();
    });

    test('addNewPageAt inserts page at specific position', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      // Add pages at the end
      await pdfDoc.appendBlankPage(CraftPageSize.A4); // Page 1
      await pdfDoc.appendBlankPage(CraftPageSize.A4); // Page 2
      await pdfDoc.appendBlankPage(CraftPageSize.A4); // Page 3

      expect(pdfDoc.pageTotal(), 3);

      // Insert a new page at position 2 (becomes new page 2)
      await pdfDoc.insertBlankPage(2, CraftPageSize.letter);

      expect(pdfDoc.pageTotal(), 4);

      await pdfDoc.close();

      // Verify the file was created
      final file = File(outPath);
      expect(file.existsSync(), true);
    });

    test('addPage adds existing page to document', () async {
      final writer = CraftPdfWriter.toFile(outPath);
      final pdfDoc = CraftPdfDocument.create(writer);

      final page = CraftPdfPage(CraftPdfDictionary());
      page.setMediaBounds(CraftPageSize.A4);

      await pdfDoc.appendPageObject(page);

      expect(pdfDoc.pageTotal(), 1);

      await pdfDoc.close();
    });
  });
}
