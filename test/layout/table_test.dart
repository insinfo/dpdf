import 'dart:typed_data';

import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/layout/document.dart';
import 'package:dpdf/src/layout/element/cell.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/table.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:test/test.dart';

/// Builds a one-page document around [build] and returns the text the package
/// extracts from the first page, so a table that never reached the page cannot
/// pass for a table that did.
Future<String> _firstPageText(void Function(Document doc) build) async {
  final output = BytesBuilder(copy: false);
  final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final doc = Document(pdf);
  build(doc);
  await doc.close();
  await pdf.close();

  final reopened =
      await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
  try {
    return await PdfTextExtraction.fromPage((await reopened.pageAt(1))!);
  } finally {
    await reopened.close();
  }
}

void main() {
  group('Table Layout Tests', () {
    test('every cell of a simple table is drawn', () async {
      final text = await _firstPageText((doc) {
        final table = Table.fromPointColumnWidths([100, 100, 100]);
        for (int i = 0; i < 9; i++) {
          table.addCell(Cell().add(Paragraph().add(Text('Cell $i'))));
        }
        doc.add(table);
      });

      for (int i = 0; i < 9; i++) {
        expect(text, contains('Cell $i'));
      }
    });

    test('colspan and rowspan cells are drawn as well', () async {
      final text = await _firstPageText((doc) {
        final table = Table.fromPointColumnWidths([100, 100, 100]);

        table.addCell(Cell().add(Paragraph().add(Text('1,1'))));
        table.addCell(Cell().add(Paragraph().add(Text('1,2'))));
        table.addCell(Cell().add(Paragraph().add(Text('1,3'))));

        // Row 2 containing a colspanned cell
        table.addCell(
            Cell(1, 2).add(Paragraph().add(Text('2,1-2 (Colspan 2)'))));
        table.addCell(Cell().add(Paragraph().add(Text('2,3'))));

        // Row 3 containing a rowspanned cell
        table.addCell(
            Cell(2, 1).add(Paragraph().add(Text('3-4,1 (Rowspan 2)'))));
        table.addCell(Cell().add(Paragraph().add(Text('3,2'))));
        table.addCell(Cell().add(Paragraph().add(Text('3,3'))));

        // Row 4 (1st cell is occupied by rowspan)
        table.addCell(Cell().add(Paragraph().add(Text('4,2'))));
        table.addCell(Cell().add(Paragraph().add(Text('4,3'))));

        doc.add(table);
      });

      expect(text, contains('2,1-2 (Colspan 2)'));
      expect(text, contains('3-4,1 (Rowspan 2)'));
      expect(text, contains('4,3'));
    });
  });
}
