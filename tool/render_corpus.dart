import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';

/// Renderiza cada pagina de um PDF com o dpdf e grava PNG, imprimindo o que o
/// relatorio de renderizacao diz ter deixado de fora.
///
/// Faz parte do arnes de comparacao contra ferramentas independentes; veja
/// `tool/README_reference_corpus.md`.
Future<void> main(List<String> args) async {
  final entrada = args.isEmpty ? 'build/complexo/complexo.pdf' : args[0];
  final saida = args.length > 1 ? args[1] : 'build/complexo/nosso';
  final dpi = args.length > 2 ? double.parse(args[2]) : 72.0;
  Directory(saida).createSync(recursive: true);

  final bytes = Uint8List.fromList(File(entrada).readAsBytesSync());
  final doc = await PdfDocument.open(PdfReader.fromBytes(bytes));

  var n = 0;
  while (n < 100) {
    PdfPage? pagina;
    try {
      pagina = await doc.pageAt(n + 1);
    } on RangeError {
      break;
    }
    if (pagina == null) break;
    n++;

    try {
      final r = await PdfPageRenderer.render(pagina,
          options: PdfRenderOptions(dpi: dpi));
      File('$saida/p$n.png').writeAsBytesSync(r.toPng());
      final buf = StringBuffer('p$n  ${r.width}x${r.height}');
      if (r.report.imagesSkipped > 0) {
        buf.write('  imagensPuladas=${r.report.imagesSkipped}');
      }
      if (r.report.glyphsSkipped > 0) {
        buf.write('  glifosPulados=${r.report.glyphsSkipped}');
      }
      if (r.report.unsupportedOperators.isNotEmpty) {
        buf.write('  naoSuportado=${r.report.unsupportedOperators}');
      }
      print(buf);
    } catch (e) {
      print('p$n  RENDER FALHOU: $e');
    }
  }
  print('paginas: $n');
}
