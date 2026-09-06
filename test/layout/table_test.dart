import 'dart:io';

import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/layout/document.dart';
import 'package:dpdf/src/layout/element/cell.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/table.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:test/test.dart';

void main() {
  group('Table Layout Tests', () {
    test('Table Basic Test', () async {
      final file = File('test/tmp/table_basic_test.pdf');
      if (await file.exists()) {
        await file.delete();
      }

      final writer = PdfWriter(file.openWrite());
      final pdf = await PdfDocument.create(writer);
      final doc = Document(pdf);

      final table = Table.fromPointColumnWidths([100, 100, 100]);

      for (int i = 0; i < 9; i++) {
        table.addCell(Cell().add(Paragraph().add(Text("Cell $i"))));
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

      final writer = PdfWriter(file.openWrite());
      final pdf = await PdfDocument.create(writer);
      final doc = Document(pdf);

      final table = Table.fromPointColumnWidths([100, 100, 100]);

      // Row 1
      table.addCell(Cell().add(Paragraph().add(Text("1,1"))));
      table.addCell(Cell().add(Paragraph().add(Text("1,2"))));
      table.addCell(Cell().add(Paragraph().add(Text("1,3"))));

      // Row 2 containing a colspanned cell
      table.addCell(Cell(1, 2).add(Paragraph().add(Text("2,1-2 (Colspan 2)"))));
      table.addCell(Cell().add(Paragraph().add(Text("2,3"))));

      // Row 3 containing a rowspanned cell
      Cell rowspanCell =
          Cell(2, 1).add(Paragraph().add(Text("3-4,1 (Rowspan 2)")));
      table.addCell(rowspanCell);
      table.addCell(Cell().add(Paragraph().add(Text("3,2"))));
      table.addCell(Cell().add(Paragraph().add(Text("3,3"))));

      // Row 4 (1st cell is occupied by rowspan)
      table.addCell(Cell().add(Paragraph().add(Text("4,2"))));
      table.addCell(Cell().add(Paragraph().add(Text("4,3"))));

      doc.add(table);

      await doc.close();

      expect(await file.exists(), isTrue);
    });
  });
}
