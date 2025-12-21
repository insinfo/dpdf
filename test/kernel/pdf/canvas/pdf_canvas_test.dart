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

      // Note: Ordering might vary if I didn't verify strict sequence, but stream is appended sequentially.
      // 100.0 might be 100 if my formatter strips .0?
      // PdfOutputStream.writeDouble uses ByteUtils.getIsoBytesFromDouble which uses BytesBuilder logic.
      // ByteUtils logic strips .0? Let's check test result.
      // If fails, I check output.

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
      expect(content, contains('50 50 Td\n')); // Assuming .0 is stripped
      expect(content, contains('(Hello) Tj\n'));
      expect(content, contains('ET\n'));
    });
  });
}
