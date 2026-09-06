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
      final writer = PdfWriter.fromBytesBuilder(builder);
      final pdfDoc = PdfDocument(writer: writer);

      await pdfDoc.addNewPage();
      await pdfDoc.addNewPage();
      await pdfDoc.addNewPage();

      expect(pdfDoc.getNumberOfPages(), 3);
      await pdfDoc.close();

      final reader = PdfReader.fromBytes(builder.toBytes());
      final readDoc = await PdfDocument.open(reader);
      expect(readDoc.getNumberOfPages(), 3);
      await readDoc.close();
    });

    test('Add and remove pages', () async {
      final builder = BytesBuilder();
      final writer = PdfWriter.fromBytesBuilder(builder);
      final pdfDoc = PdfDocument(writer: writer);

      await pdfDoc.addNewPage();
      final page2 = await pdfDoc.addNewPage();
      await pdfDoc.addNewPage();

      expect(pdfDoc.getNumberOfPages(), 3);
      
      await pdfDoc.removePage(page2);
      expect(pdfDoc.getNumberOfPages(), 2);
      
      await pdfDoc.close();
      
      final reader = PdfReader.fromBytes(builder.toBytes());
      final readDoc = await PdfDocument.open(reader);
      expect(readDoc.getNumberOfPages(), 2);
      await readDoc.close();
    });

    test('Copy pages within same document (Duplication)', () async {
      final builder = BytesBuilder();
      final writer = PdfWriter.fromBytesBuilder(builder);
      final pdfDoc = PdfDocument(writer: writer);

      await pdfDoc.addNewPage(); // Page 1
      await pdfDoc.addNewPage(); // Page 2

      expect(pdfDoc.getNumberOfPages(), 2);

      // Duplicate all pages at the end
      await pdfDoc.copyPagesTo([1, 2], pdfDoc);
      
      expect(pdfDoc.getNumberOfPages(), 4);
      
      await pdfDoc.close();
      
      final reader = PdfReader.fromBytes(builder.toBytes());
      final readDoc = await PdfDocument.open(reader);
      expect(readDoc.getNumberOfPages(), 4);
      await readDoc.close();
    });

    test('Remove page with outlines', () async {
      final builder = BytesBuilder();
      final writer = PdfWriter.fromBytesBuilder(builder);
      final pdfDoc = PdfDocument(writer: writer);

      final page1 = await pdfDoc.addNewPage();
      final page2 = await pdfDoc.addNewPage();

      final outlines = await pdfDoc.getCatalog().getOutlines(true);
      if (outlines != null) {
        final o1 = await outlines.addOutline('Page 1');
        o1.addDestination(PdfExplicitDestination.createFit(page1));
        
        final o2 = await outlines.addOutline('Page 2');
        o2.addDestination(PdfExplicitDestination.createFit(page2));
      }

      expect(pdfDoc.getNumberOfPages(), 2);
      
      // Remove page 2
      await pdfDoc.removePage(page2);
      
      expect(pdfDoc.getNumberOfPages(), 1);
      
      await pdfDoc.close();
      
      final reader = PdfReader.fromBytes(builder.toBytes());
      final readDoc = await PdfDocument.open(reader);
      expect(readDoc.getNumberOfPages(), 1);
      
      // Check outlines
      final readOutlines = await readDoc.getCatalog().getOutlines(false);
      // The root outline should have only 1 child now
      expect(readOutlines?.getAllChildren().length, 1);
      expect(readOutlines?.getAllChildren()[0].getTitle(), 'Page 1');
      
      await readDoc.close();
    });
  });
}
