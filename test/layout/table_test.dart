import 'dart:io';

import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_writer.dart';
import 'package:pdfcraft/src/layout/document.dart';
import 'package:pdfcraft/src/layout/element/cell.dart';
import 'package:pdfcraft/src/layout/element/paragraph.dart';
import 'package:pdfcraft/src/layout/element/table.dart';
import 'package:pdfcraft/src/layout/element/text.dart';
import 'package:test/test.dart';

void main() {
  group('Table Layout Tests', () {
    test('Table Basic Test', () async {
      final file = File('test/tmp/table_basic_test.pdf');
      if (await file.exists()) {
        await file.delete();
      }

      final writer = CraftPdfWriter(file.openWrite());
      final pdf = await CraftPdfDocument.create(writer);
      final doc = CraftDocument(pdf);

      final table = CraftTable.fromPointColumnWidths([100, 100, 100]);

      for (int i = 0; i < 9; i++) {
        table.addCell(
            CraftCell().add(CraftParagraph().add(CraftText("Cell $i"))));
      }

      doc.add(table);

      await doc.close();

      expect(await file.exists(), isTrue);
    });

    test('Table Colspan/Rowspan Test', () async {
      final file = File('test/tmp/table_span_test.pdf');
      if (await file.exists()) {
        await file.delete();
      }

      final writer = CraftPdfWriter(file.openWrite());
      final pdf = await CraftPdfDocument.create(writer);
      final doc = CraftDocument(pdf);

      final table = CraftTable.fromPointColumnWidths([100, 100, 100]);

      // Row 1
      table.addCell(CraftCell().add(CraftParagraph().add(CraftText("1,1"))));
      table.addCell(CraftCell().add(CraftParagraph().add(CraftText("1,2"))));
      table.addCell(CraftCell().add(CraftParagraph().add(CraftText("1,3"))));

      // Row 2 containing a colspanned cell
      table.addCell(CraftCell(1, 2)
          .add(CraftParagraph().add(CraftText("2,1-2 (Colspan 2)"))));
      table.addCell(CraftCell().add(CraftParagraph().add(CraftText("2,3"))));

      // Row 3 containing a rowspanned cell
      CraftCell rowspanCell = CraftCell(2, 1)
          .add(CraftParagraph().add(CraftText("3-4,1 (Rowspan 2)")));
      table.addCell(rowspanCell);
      table.addCell(CraftCell().add(CraftParagraph().add(CraftText("3,2"))));
      table.addCell(CraftCell().add(CraftParagraph().add(CraftText("3,3"))));

      // Row 4 (1st cell is occupied by rowspan)
      table.addCell(CraftCell().add(CraftParagraph().add(CraftText("4,2"))));
      table.addCell(CraftCell().add(CraftParagraph().add(CraftText("4,3"))));

      doc.add(table);

      await doc.close();

      expect(await file.exists(), isTrue);
    });
  });
}
