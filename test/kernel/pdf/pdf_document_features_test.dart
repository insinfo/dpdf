import 'dart:io';

import 'package:dpdf/src/kernel/pdf/filespec/pdf_file_spec.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:test/test.dart';

void main() {
  group('PdfDocument Features Tests', () {
    late String outputPath;
    late PdfDocument pdfDoc;

    setUp(() async {
      outputPath = 'test/tmp/pdf_document_features_test.pdf';
      final file = File(outputPath);
      if (await file.exists()) {
        await file.delete();
      }
      final writer = PdfWriter.toFile(outputPath);
      pdfDoc = PdfDocument.fromWriter(writer);
      await pdfDoc.addNewPage(); // Add one page
    });

    tearDown(() async {
      if (!pdfDoc.isClosed()) {
        await pdfDoc.close();
      }
    });

    test('addFileAttachment adds entry to EmbeddedFiles in Catalog', () async {
      final fsDict = PdfDictionary();
      // Minimal dictionary for FileSpec
      final fs = PdfFileSpec(fsDict);
      await pdfDoc.addFileAttachment('TestAttachment', fs);

      final catalog = pdfDoc.getCatalog();
      final names = await catalog.getPdfObject().getAsDictionary(PdfName.names);
      expect(names, isNotNull);
      final embeddedFiles = await names!.getAsDictionary(PdfName.embeddedFiles);
      expect(embeddedFiles, isNotNull);

      // Verify key presence logic
      final namesArr = await embeddedFiles!.getAsArray(PdfName.names);
      expect(namesArr, isNotNull);
      bool found = false;
      for (int i = 0; i < namesArr!.size(); i++) {
        final item = await namesArr.get(i);
        if (item is PdfString && item.getValue() == 'TestAttachment') {
          found = true;
          break;
        }
      }
      expect(found, isTrue);
    });

    test('addNamedDestination adds entry to Dests in Catalog', () async {
      final destValue = PdfArray.fromList([PdfName('Fit')]);
      await pdfDoc.addNamedDestination('MyDest', destValue);

      final catalog = pdfDoc.getCatalog();
      final names = await catalog.getPdfObject().getAsDictionary(PdfName.names);
      expect(names, isNotNull);
      final dests = await names!.getAsDictionary(PdfName.dests);
      expect(dests, isNotNull);

      // Verify key presence
      final namesArr = await dests!.getAsArray(PdfName.names);
      expect(namesArr, isNotNull);
      bool found = false;
      for (int i = 0; i < namesArr!.size(); i++) {
        final item = await namesArr.get(i);
        if (item is PdfString && item.getValue() == 'MyDest') {
          found = true;
          break;
        }
      }
      expect(found, isTrue);
    });

    test('removePageAt cleans up (basic check)', () async {
      await pdfDoc.addNewPage(); // Page 2
      expect(pdfDoc.getNumberOfPages(), 2);

      await pdfDoc.removePageAt(2);
      expect(pdfDoc.getNumberOfPages(), 1);
      // We can't easily check if outlines/widgets were removed without mocking,
      // but we verify no crash happens.
    });

    test('hasOutlines returns false initially', () {
      expect(pdfDoc.hasOutlines(), isFalse);
    });

    test('initializeOutlines creates root outline', () {
      expect(pdfDoc.hasOutlines(), isFalse);
      pdfDoc.initializeOutlines();
      expect(pdfDoc.hasOutlines(), isTrue);
    });

    test('addOutline adds nested outlines', () async {
      pdfDoc.initializeOutlines();
      final root = await pdfDoc.getOutlines(false);
      expect(root, isNotNull);

      final chapter1 = await root!.addOutline('Chapter 1');
      expect(chapter1.getTitle(), 'Chapter 1');

      final section1 = await chapter1.addOutline('Section 1.1');
      expect(section1.getTitle(), 'Section 1.1');

      // Verify hierarchy (basic check via getAllChildren)
      expect(root.getAllChildren().length, 1);
      expect(chapter1.getAllChildren().length, 1);
    });
  });
}
