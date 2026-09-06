import 'dart:io';
import 'package:test/test.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_writer.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_reader.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_name.dart';

void main() {
  group('PdfDocument Info Tests', () {
    test('Set and Get Info', () async {
      final outDir = Directory('test/tmp');
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
      final outPath = 'test/tmp/pdf_document_info_test.pdf';

      final writer = CraftPdfWriter.toFile(outPath);
      final doc = CraftPdfDocument(writer: writer);

      final info = await doc.documentDetails();
      info.setTitle('Test Title');
      info.setAuthor('Test Author');

      final title =
          await info.pdfRepresentation().stringEntry(CraftPdfName.title);
      expect(title?.decodeMappingText(), 'Test Title');

      final author =
          await info.pdfRepresentation().stringEntry(CraftPdfName.author);
      expect(author?.decodeMappingText(), 'Test Author');

      await doc.close();
    });

    test('Get Original and Modified Document IDs', () async {
      final outDir = Directory('test/tmp');
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
      final outPath = 'test/tmp/pdf_document_id_test.pdf';
      final writer = CraftPdfWriter.toFile(outPath);
      final doc = CraftPdfDocument(writer: writer);

      // IDs should be generated
      final originalId = doc.initialDocumentIdentifier();
      final modifiedId = doc.revisionIdentifier();

      expect(originalId, isNotNull);
      expect(modifiedId, isNotNull);
      // expect(originalId, equals(modifiedId)); // Often they are same initially, or different?

      await doc.close();

      // Read back
      final reader = await CraftPdfReader.fromFile(outPath);
      final docRead = await CraftPdfDocument.open(reader);

      final readOriginalId = docRead.initialDocumentIdentifier();
      final readModifiedId = docRead.revisionIdentifier();

      expect(
          readOriginalId.getValueBytes(), equals(originalId.getValueBytes()));
      // Modified ID might stay same if not saved again, or?
      // When we closed 'doc', it wrote the trailer with IDs.
      // So variables originalId/modifiedId came from 'doc' memory.
      // They should check out.
      expect(
          readModifiedId.getValueBytes(), equals(modifiedId.getValueBytes()));

      await docRead.close();
    });
  });
}
