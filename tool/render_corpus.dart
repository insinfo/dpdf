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
  // Quarto argumento `sem-substituicao` mostra o que o documento traz de
  // fato, sem as URW embutidas: e a medida de quanto a substituicao cobre.
  final substituir = !args.contains('sem-substituicao');
  // `paginas=N` limita quantas paginas renderizar. Um diario oficial tem
  // milhares; a primeira pagina ja diz se o documento abre e desenha.
  final limite = int.tryParse(
          args.firstWhere((a) => a.startsWith('paginas='), orElse: () => '')
              .replaceFirst('paginas=', '')) ??
      100;
  Directory(saida).createSync(recursive: true);

  final bytes = Uint8List.fromList(File(entrada).readAsBytesSync());
  final doc = await PdfDocument.open(PdfReader.fromBytes(bytes));

  var n = 0;
  while (n < limite) {
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
          options: PdfRenderOptions(dpi: dpi, useStandardFonts: substituir));
      File('$saida/p$n.png').writeAsBytesSync(r.toPng());
      final buf = StringBuffer('p$n  ${r.width}x${r.height}');
      if (r.report.imagesSkipped > 0) {
        buf.write('  imagensPuladas=${r.report.imagesSkipped}');
      }
      if (r.report.glyphsSkipped > 0) {
        buf.write('  glifosPulados=${r.report.glyphsSkipped}');
      }
      // Uma substituicao desenha o texto com outra tipografia. A comparacao
      // contra o MuPDF so faz sentido sabendo quais fontes nao sao as do
      // documento: as larguras sao do PDF, os contornos nao.
      if (r.report.fontsSubstituted.isNotEmpty) {
        buf.write('  fontesSubstituidas='
            '${r.report.fontsSubstituted.join(',')}');
      }
      if (r.report.unsupportedOperators.isNotEmpty) {
        buf.write('  naoSuportado=${r.report.unsupportedOperators}');
      }
      buf.write('  tinta=${_tinta(r).toStringAsFixed(1)}');
      print(buf);
    } catch (e) {
      print('p$n  RENDER FALHOU: $e');
    }
  }
  print('paginas: $n');
}

/// Quanta tinta a pagina recebeu: soma de (255 - luminancia) / 255.
///
/// Uma pagina em branco da zero. E a medida mais simples que distingue "o
/// texto foi desenhado" de "o texto sumiu" sem depender de comparar pixels.
double _tinta(PdfRenderedPage pagina) {
  var total = 0.0;
  for (final pixel in pagina.pixels) {
    final r = (pixel >>> 16) & 0xFF;
    final g = (pixel >>> 8) & 0xFF;
    final b = pixel & 0xFF;
    final v = (r + g + b) / 3.0;
    total += (255 - v) / 255.0;
  }
  return total;
}
