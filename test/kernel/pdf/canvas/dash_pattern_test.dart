import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// The content stream a canvas produced, as text.
Future<String> _content(void Function(PdfCanvas canvas) draw) async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  final canvas = await PdfCanvas.fromPage(page);
  draw(canvas);
  final stream = canvas.contentStream!;
  final bytes = await stream.getBytes();
  await document.close();
  return latin1.decode(bytes ?? Uint8List(0), allowInvalid: true);
}

void main() {
  group('setDashPattern writes in order', () {
    test('emits the array, the phase and the operator, in that order',
        () async {
      final text = await _content((canvas) {
        canvas.setDashPattern(PdfArray.fromDoubles([3, 2]), 1);
      });

      // Regressão: `writePdfObject` devolve um Future e era chamado dentro de
      // uma cascata síncrona, sem `await`. Os bytes do array chegavam ao fluxo
      // DEPOIS dos operadores seguintes, e o conteúdo inteiro saía corrompido.
      expect(text, contains('[3 2] 1 d'),
          reason: 'a saída precisa ser o array, a fase e o operador, nesta '
              'ordem; qualquer outra coisa é escrita fora de sequência');
    });

    test('does not disturb the operators that follow it', () async {
      final text = await _content((canvas) {
        canvas
          ..setDashPattern(PdfArray.fromDoubles([3, 2]), 0)
          ..setLineWidth(1.5)
          ..moveTo(10, 10)
          ..lineTo(90, 90)
          ..stroke();
      });

      final dash = text.indexOf(' d');
      final width = text.indexOf(' w');
      final move = text.indexOf(' m');
      expect(dash, isNonNegative);
      expect(width, greaterThan(dash),
          reason: 'a largura é emitida depois do tracejado');
      expect(move, greaterThan(width));
      // O sintoma do defeito era o array reaparecendo no fim, depois de
      // operadores que vieram depois dele no código.
      expect(text.lastIndexOf('['), lessThan(width),
          reason: 'nenhum resto do array pode aparecer após os operadores '
              'seguintes');
    });

    test('an empty array turns dashing off', () async {
      final text = await _content((canvas) {
        canvas.setDashPattern(PdfArray(), 0);
      });

      expect(text, contains('[] 0 d'));
    });
  });
}
