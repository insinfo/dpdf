import 'dart:io';
import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/geom/page_size.dart';

void main() {
  group('PdfDocument Move Page Tests', () {
    late String outPath;
    late PdfDocument doc;

    setUp(() async {
      final outDir = Directory('test/tmp');
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
      outPath = 'test/tmp/pdf_document_move_page_test.pdf';
      final writer = PdfWriter.toFile(outPath);
      doc = PdfDocument(writer: writer);
      await doc.addNewPage(PageSize.A4); // Page 1
      await doc.addNewPage(PageSize.A4); // Page 2
      await doc.addNewPage(PageSize.A4); // Page 3
    });

    tearDown(() async {
      await doc.close();
    });

    test('Move Page 3 to 1', () async {
      expect(doc.getNumberOfPages(), 3);
      final p1 = await doc.getPage(1);
      final p2 = await doc.getPage(2);
      final p3 = await doc.getPage(3);

      expect(p1!.getPdfObject(), isNotNull);
      expect(p3!.getPdfObject(), isNotNull);
      expect(p1.getPdfObject(), isNot(equals(p3.getPdfObject())));

      await doc.movePageAt(3, 1);

      expect(doc.getNumberOfPages(), 3);

      final newP1 = await doc.getPage(1);
      final newP2 = await doc.getPage(2);
      final newP3 = await doc.getPage(3);

      // Verify locations
      expect(newP1!.getPdfObject(), equals(p3.getPdfObject()));
      expect(newP2!.getPdfObject(), equals(p1.getPdfObject()));
      expect(newP3!.getPdfObject(), equals(p2!.getPdfObject()));
    });

    test('Move Page 1 to 3', () async {
      expect(doc.getNumberOfPages(), 3);
      final p1 = await doc.getPage(1);
      final p2 = await doc.getPage(2);
      final p3 = await doc.getPage(3);

      await doc.movePageAt(1, 4); // Insert before 4 (end)

      final newP1 = await doc.getPage(1);
      final newP2 = await doc.getPage(2);
      final newP3 = await doc.getPage(3);

      expect(newP1!.getPdfObject(), equals(p2!.getPdfObject()));
      expect(newP2!.getPdfObject(), equals(p3!.getPdfObject()));
      expect(newP3!.getPdfObject(), equals(p1!.getPdfObject()));
    });
  });
}
