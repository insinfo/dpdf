import 'dart:io';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/kernel/font/pdf_true_type_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_resources.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:test/test.dart';

void main() {
  group('PdfTrueTypeFont', () {
    test('Load Arial and write text', () async {
      String fontPath = r'C:\MyDartProjects\itext\test\assets\arial.ttf';
      if (!File(fontPath).existsSync()) {
        print("Skipping test: arial.ttf not found at $fontPath");
        return;
      }

      File file = File('test_ttf.pdf');
      final writer = PdfWriter.toFile(file.path);
      final doc = await PdfDocument.create(writer);

      final resources = PdfResources();
      final stream = PdfStream();
      final canvas = PdfCanvas(stream, resources, doc);

      // Load font using FontProgramFactory (assuming it works for TTF)
      // Or manually create TrueTypeFont
      // TrueTypeFont ttf = TrueTypeFont(fontPath); // Default read
      // We haven't exposed TrueTypeFont constructor nicely or factory yet.

      // Let's rely on OpenTypeParser logic via TrueTypeFont constructor if available?
      // TrueTypeFont constructor accepts String path.

      final ttf = TrueTypeFont.fromFile(fontPath);
      final font = PdfTrueTypeFont(ttf, "WinAnsiEncoding", true); // Embedded

      await canvas.setFontAndSize(font, 12);
      canvas.beginText().moveText(50, 700).showText("Hello Arial").endText();

      final bytes = await stream.getBytes();
      final content = String.fromCharCodes(bytes!);

      print("Content: $content");

      expect(content, contains('(Hello Arial) Tj'));
      // Check if font resource is added is hard without parsing resource dictionary
      // But make sure no exception thrown.

      writer.close();
      if (await file.exists()) file.deleteSync();
    });
  });
}
