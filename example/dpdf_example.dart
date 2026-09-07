import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';

/// Um passeio pelas quatro coisas que a biblioteca faz com mais frequência:
/// converter HTML, inspecionar um arquivo, verificar conformidade e redigir.
///
/// Execute a partir da raiz do pacote:
///
/// ```
/// dart run example/dpdf_example.dart
/// ```
///
/// Passe um diretório como argumento para gravar os PDFs gerados.
Future<void> main(List<String> arguments) async {
  final destination = arguments.isEmpty ? null : Directory(arguments.first);

  final relatorio = await _converterHtml();
  await _salvar(destination, 'relatorio.html.pdf', relatorio);

  await _inspecionar(relatorio);
  await _verificarConformidade(relatorio);

  final redigido = await _redigirPorArea();
  await _salvar(destination, 'redigido.pdf', redigido);
}

/// HTML para PDF. O conversor mede o texto com as métricas da face que ele
/// mesmo vai desenhar, então a quebra de linha e o alinhamento são exatos.
Future<Uint8List> _converterHtml() async {
  const html = '''
    <html><body>
      <h1 style="font-family: serif">Relatório trimestral</h1>
      <p>Este parágrafo é quebrado em linhas com as larguras reais da
         Helvetica, não com uma largura média estimada.</p>
      <table>
        <tr><th>Item</th><th>Valor</th></tr>
        <tr><td>Licenças</td><td>R\$ 12.400</td></tr>
        <tr><td>Suporte</td><td>R\$ 3.100</td></tr>
      </table>
      <p style="font-family: monospace">Rodapé em Courier.</p>
    </body></html>
  ''';

  final bytes = await HtmlConverter.convertToBytes(html);
  print('HTML convertido: ${bytes.length} bytes');
  return bytes;
}

/// Inspeção estrutural: o arquivo abre, e o que quebraria um leitor.
Future<void> _inspecionar(Uint8List bytes) async {
  final report = await PdfIntegrityChecker.inspect(bytes);

  print('\nIntegridade');
  print('  legível ............ ${report.readable}');
  print('  danificado ......... ${report.isDamaged}');
  print('  páginas ............ ${report.reachablePageCount}');
  print('  objetos ............ ${report.objectCount}');
  print('  versão do cabeçalho  ${report.headerVersion}');
  for (final finding in report.findings) {
    print('  $finding');
  }
}

/// Conformidade PDF/A: o relatório também diz o que não foi avaliado, para
/// que um resultado limpo não seja confundido com certificação.
Future<void> _verificarConformidade(Uint8List bytes) async {
  final report = await PdfAVerifier.verify(
    bytes,
    level: PdfAConformanceLevel.a2b,
  );

  print('\nConformidade ${report.profile}');
  print('  declarado no XMP ... ${report.claimedProfile ?? 'nenhum'}');
  print('  conforme ........... ${report.isConforming}');
  for (final violation in report.violations) {
    print('  ${violation.code} (${violation.clause})');
  }
  print('  regras não avaliadas: ${report.unverifiedRules.length}');
}

/// Redação por área: remove do fluxo de conteúdo os caracteres dentro do
/// retângulo e cobre a região com uma tarja opaca.
Future<Uint8List> _redigirPorArea() async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  final canvas = await PdfCanvas.fromPage(page);
  canvas.beginText();
  await canvas.setFontAndSize(PdfFontFactory.createFont('Helvetica'), 12);
  canvas
      .moveText(72, 700)
      .showText('Cliente: Maria Souza')
      .moveText(0, -20)
      .showText('CPF: 123.456.789-00')
      .moveText(0, -20)
      .showText('Total: R\$ 1.250,00')
      .endText();
  await document.close();
  final original = output.takeBytes();

  final redigido = await PdfAreaRedaction.apply(original, [
    // A linha do CPF, em coordenadas de usuário da página.
    PdfRedactionArea(1, left: 70, bottom: 675, right: 300, top: 693),
  ]);

  final reader = PdfReader.fromBytes(redigido);
  final reaberto = await PdfDocument.open(reader);
  try {
    final texto = await PdfTextExtraction.fromPage((await reaberto.pageAt(1))!);
    print('\nRedação');
    print('  CPF ainda presente: ${texto.contains('123.456.789-00')}');
    print('  nome preservado ..: ${texto.contains('Maria Souza')}');
  } finally {
    await reaberto.close();
  }
  return redigido;
}

Future<void> _salvar(
    Directory? destination, String name, Uint8List bytes) async {
  if (destination == null) return;
  await destination.create(recursive: true);
  final file = File('${destination.path}/$name');
  await file.writeAsBytes(bytes);
  print('gravado: ${file.path}');
}
