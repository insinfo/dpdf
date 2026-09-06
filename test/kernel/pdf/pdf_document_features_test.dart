import 'dart:io';

import 'package:pdfcraft/src/kernel/pdf/filespec/pdf_file_spec.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_array.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_dictionary.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_name.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_writer.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_string.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => Directory('test/tmp').createSync(recursive: true));
  group('PdfDocument Features Tests', () {
    late String outputPath;
    late CraftPdfDocument pdfDoc;

    setUp(() async {
      outputPath = 'test/tmp/pdf_document_features_test.pdf';
      final file = File(outputPath);
      if (await file.exists()) {
        await file.delete();
      }
      final writer = CraftPdfWriter.toFile(outputPath);
      pdfDoc = CraftPdfDocument.fromWriter(writer);
      await pdfDoc.appendBlankPage(); // Add one page
    });

    tearDown(() async {
      if (!pdfDoc.lifecycleClosed()) {
        await pdfDoc.close();
      }
    });

    test('addFileAttachment adds entry to EmbeddedFiles in Catalog', () async {
      final fsDict = CraftPdfDictionary();
      // Minimal dictionary for FileSpec
      final fs = CraftPdfFileSpec(fsDict);
      await pdfDoc.registerAttachment('TestAttachment', fs);

      final catalog = pdfDoc.rootCatalog();
      final names =
          await catalog.pdfRepresentation().dictionaryEntry(CraftPdfName.names);
      expect(names, isNotNull);
      final embeddedFiles =
          await names!.dictionaryEntry(CraftPdfName.embeddedFiles);
      expect(embeddedFiles, isNotNull);

      // Verify key presence logic
      final namesArr = await embeddedFiles!.arrayEntry(CraftPdfName.names);
      expect(namesArr, isNotNull);
      bool found = false;
      for (int i = 0; i < namesArr!.size(); i++) {
        final item = await namesArr.get(i);
        if (item is CraftPdfString && item.getValue() == 'TestAttachment') {
          found = true;
          break;
        }
      }
      expect(found, isTrue);
    });

    test('addNamedDestination adds entry to Dests in Catalog', () async {
      final destValue = CraftPdfArray.fromList([CraftPdfName('Fit')]);
      await pdfDoc.registerDestination('MyDest', destValue);

      final catalog = pdfDoc.rootCatalog();
      final names =
          await catalog.pdfRepresentation().dictionaryEntry(CraftPdfName.names);
      expect(names, isNotNull);
      final dests = await names!.dictionaryEntry(CraftPdfName.dests);
      expect(dests, isNotNull);

      // Verify key presence
      final namesArr = await dests!.arrayEntry(CraftPdfName.names);
      expect(namesArr, isNotNull);
      bool found = false;
      for (int i = 0; i < namesArr!.size(); i++) {
        final item = await namesArr.get(i);
        if (item is CraftPdfString && item.getValue() == 'MyDest') {
          found = true;
          break;
        }
      }
      expect(found, isTrue);
    });

    test('removePageAt cleans up (basic check)', () async {
      await pdfDoc.appendBlankPage(); // Page 2
      expect(pdfDoc.pageTotal(), 2);

      await pdfDoc.deletePageAt(2);
      expect(pdfDoc.pageTotal(), 1);
      // We can't easily check if outlines/widgets were removed without mocking,
      // but we verify no crash happens.
    });

    test('hasOutlines returns false initially', () {
      expect(pdfDoc.containsOutlineTree(), isFalse);
    });

    test('initializeOutlines creates root outline', () {
      expect(pdfDoc.containsOutlineTree(), isFalse);
      pdfDoc.initializeOutlineTree();
      expect(pdfDoc.containsOutlineTree(), isTrue);
    });

    test('addOutline adds nested outlines', () async {
      pdfDoc.initializeOutlineTree();
      final root = await pdfDoc.outlineTree(false);
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
