import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// Builds a document with enough pages and content for the first-page section
/// to be a real subset of the file.
Future<Uint8List> _document({int pages = 6}) async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  for (var i = 0; i < pages; i++) {
    final page = await document.appendBlankPage();
    page.pdfRepresentation().put(
        PdfName.mediaBox, PdfArray.fromDoubles([0, 0, 300, 300]));
    final canvas = await PdfCanvas.fromPage(page);
    canvas.setFillColor(DeviceRgb(i / pages, 0.2, 0.6));
    canvas.rectangle(20, 20, 200, 100 + i.toDouble());
    canvas.fill();
  }
  await document.close();
  return output.takeBytes();
}

Future<int> _countPages(Uint8List bytes) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  var count = 0;
  while (count < 1000) {
    try {
      if (await document.pageAt(count + 1) == null) break;
    } on RangeError {
      break;
    }
    count++;
  }
  return count;
}

void main() {
  group('Annex F linearization', () {
    test('a linearized file reopens with every page intact', () async {
      final source = await _document();
      final linear = await PdfLinearizer.linearize(source);

      expect(await _countPages(source), equals(6));
      expect(await _countPages(linear), equals(6));
    });

    test('the parameter dictionary is the first object of the file', () async {
      final linear = await PdfLinearizer.linearize(await _document());

      // F.3.3: the linearization parameter dictionary shall be the first
      // object, so a reader can find it without scanning the whole file.
      final head = latin1.decode(linear.sublist(0, 1024), allowInvalid: true);
      expect(head, contains('/Linearized'));
      expect(head.indexOf('/Linearized'), lessThan(head.indexOf('/Type')),
          reason: 'o dicionario de parametros vem antes de qualquer objeto '
              'comum do documento');
    });

    test('the declared /L matches the bytes actually written', () async {
      // Regressao: o tamanho do trailer da primeira pagina era estimado com
      // /Root e /Info zerados. Como esses dois sao os unicos numeros do
      // trailer escritos sem preenchimento, e /Info some por completo quando
      // vale zero, a estimativa saia menor que a realidade e o arquivo
      // planejado nao batia com o escrito.
      for (final pages in [1, 2, 6, 17]) {
        final linear = await PdfLinearizer.linearize(await _document(pages: pages));
        final info = await PdfLinearizationInfo.read(linear);
        expect(info.declaredFileLength, equals(linear.length),
            reason: '/L tem de descrever o arquivo inteiro, com $pages paginas');
      }
    });

    test('the reader reports a linearized file as valid', () async {
      final linear = await PdfLinearizer.linearize(await _document());
      final info = await PdfLinearizationInfo.read(linear);

      expect(info.isLinearized, isTrue);
      expect(info.pageCount, equals(6));
      expect(info.problems, isEmpty,
          reason: 'a saida do proprio linearizador tem de satisfazer o anexo F');
      expect(info.isValid, isTrue);
      expect(info.hintStreamSpans, isNotEmpty);
      expect(info.firstPageObjectNumber, isNotNull);
      expect(info.mainXrefOffset, isNotNull);
    });

    test('a file that was never linearized is reported as such', () async {
      final info = await PdfLinearizationInfo.read(await _document());

      expect(info.isLinearized, isFalse);
      expect(info.isValid, isFalse);
    });

    test('the page content survives the rearrangement', () async {
      final source = await _document(pages: 3);
      final linear = await PdfLinearizer.linearize(source);

      Future<List<String>> contents(Uint8List bytes) async {
        final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
        final out = <String>[];
        for (var i = 1; i <= 3; i++) {
          final page = await document.pageAt(i);
          final stream = await page!
              .pdfRepresentation()
              .streamEntry(PdfName.contents);
          final data = await stream!.getBytes(true);
          out.add(latin1.decode(data ?? Uint8List(0), allowInvalid: true));
        }
        return out;
      }

      // Linearization renumbers and reorders objects; it must not alter a
      // single byte of what the pages draw.
      expect(await contents(linear), equals(await contents(source)));
    });

    test('the result passes the integrity checker', () async {
      final linear = await PdfLinearizer.linearize(await _document());
      final report = await PdfIntegrityChecker.inspect(linear, deepScan: true);

      final serious = report.findings
          .where((f) => !f.toString().toLowerCase().contains('[info]'))
          .toList();
      expect(serious, isEmpty, reason: serious.join('\n'));
    });

    test('a single page document linearizes', () async {
      // The degenerate case: the first-page section is the whole document and
      // the second group is empty.
      final linear = await PdfLinearizer.linearize(await _document(pages: 1));
      final info = await PdfLinearizationInfo.read(linear);

      expect(info.isLinearized, isTrue);
      expect(info.pageCount, equals(1));
      expect(await _countPages(linear), equals(1));
    });
  });
}
