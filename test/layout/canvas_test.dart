import 'dart:typed_data';

import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/io/font/constants/standard_fonts.dart';
import 'package:dpdf/src/kernel/font/pdf_font_factory.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/layout/canvas.dart';
import 'package:dpdf/src/layout/element/div.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/text.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:test/test.dart';

void main() {
  group('Canvas Tests', () {
    test('a paragraph placed on a canvas reaches the page', () async {
      final output = BytesBuilder(copy: false);
      final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
      final page = await pdf.appendBlankPage();
      final pageSize = await page.mediaBounds();
      final canvas = Canvas(await PdfCanvas.fromPage(page),
          Rectangle(pageSize.getX() + 36, pageSize.getY() + 36, 200, 100));

      // A canvas carries no default font of its own, unlike a Document.
      canvas.setProperty(
          Property.FONT, PdfFontFactory.createFont(StandardFonts.HELVETICA));
      canvas.add(Paragraph()..add(Text('Hello Canvas')));

      await canvas.close();
      await pdf.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
      addTearDown(reopened.close);
      expect(await PdfTextExtraction.fromPage((await reopened.pageAt(1))!),
          contains('Hello Canvas'));
    });

    test('content that does not fit is reported when the canvas is closed',
        () async {
      final output = BytesBuilder(copy: false);
      final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
      final page = await pdf.appendBlankPage();
      final canvas =
          Canvas(await PdfCanvas.fromPage(page), Rectangle(0, 0, 100, 50));

      // add() only queues, so the rejection cannot happen here any more.
      canvas.add(Div()..setMinHeight(400));

      await expectLater(canvas.close(), throwsStateError);
      // The failed queue is not retained, so the PdfDocument closes cleanly and
      // the error is reported exactly once.
      await pdf.close();
      expect(output.length, greaterThan(0));
    });
  });
}
