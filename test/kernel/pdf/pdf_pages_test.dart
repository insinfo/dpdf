import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';

import 'package:dpdf/src/kernel/pdf/navigation/pdf_destination.dart';

void main() {
  group('PdfPages Tests', () {
    test('Create document with multiple pages and verify count', () async {
      final builder = BytesBuilder();
      final writer = CraftPdfWriter.fromBytesBuilder(builder);
      final pdfDoc = CraftPdfDocument(writer: writer);

      await pdfDoc.appendBlankPage();
      await pdfDoc.appendBlankPage();
      await pdfDoc.appendBlankPage();

      expect(pdfDoc.pageTotal(), 3);
      await pdfDoc.close();

      final reader = CraftPdfReader.fromBytes(builder.toBytes());
      final readDoc = await CraftPdfDocument.open(reader);
      expect(readDoc.pageTotal(), 3);
      await readDoc.close();
    });

    test('Add and remove pages', () async {
      final builder = BytesBuilder();
      final writer = CraftPdfWriter.fromBytesBuilder(builder);
      final pdfDoc = CraftPdfDocument(writer: writer);

      await pdfDoc.appendBlankPage();
      final page2 = await pdfDoc.appendBlankPage();
      await pdfDoc.appendBlankPage();

      expect(pdfDoc.pageTotal(), 3);

      await pdfDoc.detachPage(page2);
      expect(pdfDoc.pageTotal(), 2);

      await pdfDoc.close();

      final reader = CraftPdfReader.fromBytes(builder.toBytes());
      final readDoc = await CraftPdfDocument.open(reader);
      expect(readDoc.pageTotal(), 2);
      await readDoc.close();
    });

    test('Copy pages within same document (Duplication)', () async {
      final builder = BytesBuilder();
      final writer = CraftPdfWriter.fromBytesBuilder(builder);
      final pdfDoc = CraftPdfDocument(writer: writer);

      await pdfDoc.appendBlankPage(); // Page 1
      await pdfDoc.appendBlankPage(); // Page 2

      expect(pdfDoc.pageTotal(), 2);

      // Duplicate all pages at the end
      await pdfDoc.transferPagesInto([1, 2], pdfDoc);

      expect(pdfDoc.pageTotal(), 4);

      await pdfDoc.close();

      final reader = CraftPdfReader.fromBytes(builder.toBytes());
      final readDoc = await CraftPdfDocument.open(reader);
      expect(readDoc.pageTotal(), 4);
      await readDoc.close();
    });

    test('Remove page with outlines', () async {
      final builder = BytesBuilder();
      final writer = CraftPdfWriter.fromBytesBuilder(builder);
      final pdfDoc = CraftPdfDocument(writer: writer);

      final page1 = await pdfDoc.appendBlankPage();
      final page2 = await pdfDoc.appendBlankPage();

      final outlines = await pdfDoc.rootCatalog().outlineTree(true);
      if (outlines != null) {
        final o1 = await outlines.addOutline('Page 1');
        o1.addDestination(CraftPdfExplicitDestination.createFit(page1));

        final o2 = await outlines.addOutline('Page 2');
        o2.addDestination(CraftPdfExplicitDestination.createFit(page2));
      }

      expect(pdfDoc.pageTotal(), 2);

      // Remove page 2
      await pdfDoc.detachPage(page2);

      expect(pdfDoc.pageTotal(), 1);

      await pdfDoc.close();

      final reader = CraftPdfReader.fromBytes(builder.toBytes());
      final readDoc = await CraftPdfDocument.open(reader);
      expect(readDoc.pageTotal(), 1);

      // Check outlines
      final readOutlines = await readDoc.rootCatalog().outlineTree(false);
      // The root outline should have only 1 child now
      expect(readOutlines?.getAllChildren().length, 1);
      expect(readOutlines?.getAllChildren()[0].getTitle(), 'Page 1');

      await readDoc.close();
    });
  });
}
