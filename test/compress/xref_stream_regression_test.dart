import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// Builds a document written with a cross-reference *stream* rather than a
/// classic table, so its trailer carries `/Index` and `/W`.
Future<Uint8List> _documentWithXrefStream({int pages = 3}) async {
  final output = BytesBuilder(copy: false);
  final document = CraftPdfDocument.create(
    CraftPdfWriter.fromBytesBuilder(
      output,
      properties: CraftWriterProperties().setFullCompressionMode(true),
    ),
  );
  for (var i = 0; i < pages; i++) {
    final page = await document.appendBlankPage();
    page.pdfRepresentation()
      ..put(CraftPdfName.mediaBox, CraftPdfArray.fromDoubles([0, 0, 200, 200]))
      ..put(
        CraftPdfName.contents,
        CraftPdfStream.withBytes(
            Uint8List.fromList(latin1.encode('0 g 20 20 60 60 re f')), 0),
      );
  }
  await document.close();
  return output.takeBytes();
}

/// Injects an `/Index` into the document's cross-reference stream dictionary,
/// the way a producer that writes subsections does.
///
/// This writer always lays out a contiguous table and never emits `/Index`, so
/// a fixture it produces cannot reproduce the condition on its own. Real
/// documents — signed ones especially — routinely carry one.
///
/// The insertion is safe: the entry goes inside a dictionary that sits at the
/// very end of the file, so no object offset moves and `startxref` stays valid.
Uint8List _withXrefIndex(Uint8List source, int size) {
  final text = latin1.decode(source, allowInvalid: true);
  final marker = text.lastIndexOf('/Type /XRef');
  if (marker < 0) throw StateError('o fixture não tem stream de xref');
  final insertion = latin1.encode(' /Index [0 $size] ');
  final at = marker + '/Type /XRef'.length;
  return Uint8List.fromList(
      [...source.sublist(0, at), ...insertion, ...source.sublist(at)]);
}

Future<int> _countPages(Uint8List bytes) async {
  final document = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
  try {
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
  } finally {
    await document.close();
  }
}

/// The `/Index` entry of the last cross-reference stream, if there is one.
List<int>? _lastXrefIndex(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final match = RegExp(r'/Index\s*\[([\d\s]+)\]').allMatches(text).lastOrNull;
  if (match == null) return null;
  return match.group(1)!.trim().split(RegExp(r'\s+')).map(int.parse).toList();
}

void main() {
  group('cross-reference stream survives a rewrite', () {
    test('a document written with an xref stream reopens', () async {
      final bytes = await _documentWithXrefStream();

      expect(latin1.decode(bytes, allowInvalid: true), contains('/XRef'),
          reason: 'o fixture precisa mesmo usar stream de xref, senão o teste '
              'não exercita o caminho em questão');
      expect(await _countPages(bytes), equals(3));
    });

    test('compressing it keeps every page readable', () async {
      // Regressão: o escritor copiava todas as entradas do trailer para o novo
      // dicionário de xref, inclusive o `/Index` do documento de origem. As
      // entradas gravadas eram a tabela contígua 0..N, mas o dicionário ainda
      // declarava as subseções antigas, então o leitor associava cada entrada
      // ao objeto errado. O documento saía do compressor sem erro e não abria
      // mais — perda silenciosa.
      // O `/Index` da origem descreve a tabela ANTIGA. O compressor escreve
      // uma tabela contígua nova, com outra contagem de objetos; herdar o
      // `/Index` fazia o leitor associar cada entrada ao objeto errado.
      final original = _withXrefIndex(await _documentWithXrefStream(), 12);
      expect(await _countPages(original), equals(3),
          reason: 'o fixture precisa abrir antes de comprimir');

      final result = await PdfCompressor.compress(original);

      expect(await _countPages(result.bytes), equals(3),
          reason:
              'o documento comprimido tem de reabrir com as mesmas páginas');
    });

    test('the written /Index describes the entries actually written', () async {
      final original = _withXrefIndex(await _documentWithXrefStream(), 12);
      final result = await PdfCompressor.compress(original);

      final index = _lastXrefIndex(result.bytes);
      if (index == null) {
        // Sem `/Index`, a tabela é a contígua 0..Size, que é exatamente o que
        // este escritor produz. É o resultado correto e não há o que conferir.
        return;
      }
      // Se um `/Index` for escrito, ele precisa somar o número de entradas da
      // tabela. Pares `[primeiro, quantidade]`.
      expect(index.length.isEven, isTrue);
      var declared = 0;
      for (var i = 1; i < index.length; i += 2) {
        declared += index[i];
      }
      final size = RegExp(r'/Size\s+(\d+)')
          .allMatches(latin1.decode(result.bytes, allowInvalid: true))
          .last;
      expect(declared, equals(int.parse(size.group(1)!)),
          reason: 'um /Index que não cobre todas as entradas faz o leitor '
              'associá-las aos objetos errados');
    });

    test('a second compression round is still readable', () async {
      // Comprimir a saída de novo é o que revela um estado herdado que só se
      // manifesta a partir da segunda geração.
      final original = _withXrefIndex(await _documentWithXrefStream(), 12);
      final once = await PdfCompressor.compress(original);
      final twice = await PdfCompressor.compress(once.bytes);

      expect(await _countPages(twice.bytes), equals(3));
    });
  });
}
