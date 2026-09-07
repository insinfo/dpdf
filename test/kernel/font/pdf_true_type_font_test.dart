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
    test('Load ABeeZee and write text', () async {
      String fontPath = r'test/assets/ABeeZee-Regular.ttf';
      if (!File(fontPath).existsSync()) {
        return;
      }

      // Escrever num diretório temporário, não na raiz do repositório: um
      // teste que falha no meio não deve deixar lixo na árvore de trabalho.
      final directory = Directory.systemTemp.createTempSync('dpdf_ttf_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/test_ttf.pdf');
      final writer = PdfWriter.toFile(file.path);
      final doc = PdfDocument.create(writer);

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
      canvas.beginText().moveText(50, 700).showText("Hello ABeeZee").endText();

      final bytes = await stream.getBytes();
      final content = String.fromCharCodes(bytes!);

      expect(content, contains('(Hello ABeeZee) Tj'));
      // Check if font resource is added is hard without parsing resource dictionary
      // But make sure no exception thrown.

      // `close()` devolve um Future. Sem aguardá-lo, o arquivo continua aberto
      // e o `deleteSync` abaixo falha no Windows com errno 32 — o POSIX deixa
      // remover arquivo aberto, o Windows não. Era um teste que passava ou
      // falhava conforme a plataforma e o escalonamento.
      await writer.close();
    });
  });
}
