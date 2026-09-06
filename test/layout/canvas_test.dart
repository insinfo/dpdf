import 'dart:io';
import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';

import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/layout/canvas.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/properties/text_alignment.dart';

void main() {
  group('Canvas Tests', () {
    test('Canvas Basic Test', () async {
      final file = File('test/tmp/canvas_test_output.pdf');
      if (await file.exists()) {
        await file.delete();
      }

      final writer = PdfWriter(file.openWrite());
      final pdf = await PdfDocument.create(writer);
      final page = await pdf.addNewPage();
      final pageSize = await page.getMediaBox();

      final pdfCanvas = await PdfCanvas.fromPage(page);

      final rect =
          Rectangle(pageSize.getX() + 36, pageSize.getY() + 36, 200, 100);

      final canvas = Canvas(pdfCanvas, rect);
      Paragraph p = Paragraph();
      p.add(Text("Hello Canvas"));
      canvas.add(p);

      await canvas.close();
      await pdf.close();

      expect(await file.exists(), isTrue);
    });

    test('Canvas ShowTextAligned Test', () async {
      final file = File('test/tmp/canvas_text_aligned_test.pdf');
      if (await file.exists()) {
        await file.delete();
      }

      final writer = PdfWriter(file.openWrite());
      final pdf = await PdfDocument.create(writer);
      final page = await pdf.addNewPage();

      final pdfCanvas = await PdfCanvas.fromPage(page);
      final canvas = Canvas(pdfCanvas, await page.getMediaBox());

      canvas.showTextAligned(
          text: "Centered Text",
          x: 200,
          y: 400,
          textAlign: TextAlignment.center,
          angle: 0.785398); // 45 degrees

      await canvas.close();
      await pdf.close();

      expect(await file.exists(), isTrue);
    });
  });
}
