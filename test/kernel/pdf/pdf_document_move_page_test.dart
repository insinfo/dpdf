import 'dart:io';
import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/geom/page_size.dart';

void main() {
  group('PdfDocument Move Page Tests', () {
    late String outPath;
    late CraftPdfDocument doc;

    setUp(() async {
      final outDir = Directory('test/tmp');
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
      outPath = 'test/tmp/pdf_document_move_page_test.pdf';
      final writer = CraftPdfWriter.toFile(outPath);
      doc = CraftPdfDocument(writer: writer);
      await doc.appendBlankPage(CraftPageSize.A4); // Page 1
      await doc.appendBlankPage(CraftPageSize.A4); // Page 2
      await doc.appendBlankPage(CraftPageSize.A4); // Page 3
    });

    tearDown(() async {
      await doc.close();
    });

    test('Move Page 3 to 1', () async {
      expect(doc.pageTotal(), 3);
      final p1 = await doc.pageAt(1);
      final p2 = await doc.pageAt(2);
      final p3 = await doc.pageAt(3);

      expect(p1!.pdfRepresentation(), isNotNull);
      expect(p3!.pdfRepresentation(), isNotNull);
      expect(p1.pdfRepresentation(), isNot(equals(p3.pdfRepresentation())));

      await doc.relocatePageAt(3, 1);

      expect(doc.pageTotal(), 3);

      final newP1 = await doc.pageAt(1);
      final newP2 = await doc.pageAt(2);
      final newP3 = await doc.pageAt(3);

      // Verify locations
      expect(newP1!.pdfRepresentation(), equals(p3.pdfRepresentation()));
      expect(newP2!.pdfRepresentation(), equals(p1.pdfRepresentation()));
      expect(newP3!.pdfRepresentation(), equals(p2!.pdfRepresentation()));
    });

    test('Move Page 1 to 3', () async {
      expect(doc.pageTotal(), 3);
      final p1 = await doc.pageAt(1);
      final p2 = await doc.pageAt(2);
      final p3 = await doc.pageAt(3);

      await doc.relocatePageAt(1, 4); // Insert before 4 (end)

      final newP1 = await doc.pageAt(1);
      final newP2 = await doc.pageAt(2);
      final newP3 = await doc.pageAt(3);

      expect(newP1!.pdfRepresentation(), equals(p2!.pdfRepresentation()));
      expect(newP2!.pdfRepresentation(), equals(p3!.pdfRepresentation()));
      expect(newP3!.pdfRepresentation(), equals(p1!.pdfRepresentation()));
    });
  });
}
