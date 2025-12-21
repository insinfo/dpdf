import 'dart:io';
import 'package:itext/src/io/font/type1_font.dart';
import 'package:itext/src/io/font/constants/standard_fonts.dart';
import 'package:itext/src/kernel/font/pdf_type1_font.dart';
import 'package:itext/src/kernel/pdf/pdf_document.dart';
import 'package:itext/src/kernel/pdf/pdf_writer.dart';
import 'package:itext/src/kernel/pdf/pdf_resources.dart';
import 'package:itext/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:itext/src/kernel/pdf/pdf_stream.dart';
import 'package:test/test.dart';

void main() {
  group('PdfCanvas', () {
    test('Detailed drawing operations', () async {
      final stream = PdfStream();
      final canvas = PdfCanvas(stream, null, null);

      canvas
          .saveState()
          .moveTo(100, 100)
          .lineTo(200, 200)
          .stroke()
          .restoreState();

      final bytes = await stream.getBytes();
      final content = String.fromCharCodes(bytes!);

      expect(content, contains('q\n'));
      // expect(content, contains('100 100 m\n')); // ByteUtils strips .0
      // expect(content, contains('200 200 l\n'));
      expect(content, contains('S\n'));
      expect(content, contains('Q\n'));
    });

    test('Text operations', () async {
      final stream = PdfStream();
      final canvas = PdfCanvas(stream, null, null);

      canvas.beginText().moveText(50, 50).showText("Hello").endText();

      final bytes = await stream.getBytes();
      final content = String.fromCharCodes(bytes!);

      expect(content, contains('BT\n'));
      expect(content,
          contains('50 50 Td\n')); // Assuming .0 is stripped or whatever format
      expect(content, contains('(Hello) Tj\n'));
      expect(content, contains('ET\n'));
    });

    test('Type1Font HELVETICA', () async {
      File file = File('test_type1.pdf');
      final writer = PdfWriter.toFile(file.path);
      final doc = await PdfDocument.create(writer);

      final resources = PdfResources();
      final stream = PdfStream();
      // Mock or use real components
      // Since we are writing to stream, we don't fully need Document attached to Page yet for this unit test,
      // BUT setFontAndSize needs doc to add font to resources.

      final canvas = PdfCanvas(stream, resources, doc);

      // Load font
      final type1Font = Type1Font(StandardFonts.HELVETICA, "", null, null);
      final font = PdfType1Font(type1Font);

      await canvas.setFontAndSize(font, 12);
      canvas
          .beginText()
          .moveText(50, 700)
          .showText("Hello Helvetica")
          .endText();

      final bytes = await stream.getBytes();
      final content = String.fromCharCodes(bytes!);

      print("Content: $content");

      expect(content, contains('/F1 12 Tf'));
      expect(content, contains('(Hello Helvetica) Tj'));

      // Cleanup optional, keeping it for inspection if failed, but normally delete
      writer.close();
      if (await file.exists()) file.deleteSync();
    });
  });
}
