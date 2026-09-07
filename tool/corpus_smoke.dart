// Passa a biblioteca inteira sobre um diretório de PDFs reais e relata o que
// quebra: abertura, inspeção de integridade, renderização e compressão.
//
// Documentos de produção exercitam caminhos que nenhum fixture sintético
// alcança — xref híbrido, streams de objetos, fontes CID, campos de assinatura,
// anotações, geradores exóticos. O objetivo aqui não é afirmar que a saída está
// certa, e sim que nada estoura e que o relatório diz a verdade sobre o que
// ficou por desenhar.
import 'dart:io';

import 'package:dpdf/dpdf.dart';

/// Conta as páginas percorrendo a árvore, o que também a exercita.
Future<int> _countPages(CraftPdfDocument document) async {
  var count = 0;
  // Um limite alto impede que uma árvore com ciclo prenda o processo.
  // `pageAt` lança RangeError depois da última página, em vez de devolver
  // nulo, então o fim da árvore é sinalizado pela exceção.
  while (count < 20000) {
    try {
      if (await document.pageAt(count + 1) == null) break;
    } on RangeError {
      break;
    }
    count++;
  }
  return count;
}

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final directory = Directory(positional.isEmpty
      ? r'C:\MyDartProjects\insinfo_dart_pdf\test\assets'
      : positional.first);
  final onlyRender = args.contains('--render');
  // Um TTF passado com --fallback é usado para o texto cuja fonte o documento
  // não embute, que é o caso da maioria absoluta.
  final fallbackArg =
      args.where((a) => a.startsWith('--fallback=')).firstOrNull;
  final fallbackBytes = fallbackArg == null
      ? null
      : File(fallbackArg.substring('--fallback='.length)).readAsBytesSync();

  final files = directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.pdf'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  var opened = 0;
  var openFailed = 0;
  var rendered = 0;
  var renderFailed = 0;
  var incomplete = 0;
  var compressed = 0;
  var compressFailed = 0;
  final unsupported = <String, int>{};
  final fontFailures = <String, int>{};
  final failures = <String, String>{};

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final bytes = file.readAsBytesSync();

    // --- abertura e estrutura -----------------------------------------------
    CraftPdfDocument document;
    try {
      document = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    } catch (e) {
      openFailed++;
      failures['$name/abrir'] = '${e.runtimeType}: $e';
      print('ABRIR-FALHOU ${name.padRight(48)} ${e.runtimeType}');
      continue;
    }

    final int pages;
    try {
      pages = await _countPages(document);
    } catch (e) {
      openFailed++;
      failures['$name/paginas'] = '${e.runtimeType}: $e';
      await document.close();
      continue;
    }
    opened++;

    // --- renderização da primeira página ------------------------------------
    var note = '';
    try {
      final page = await document.pageAt(1);
      if (page != null) {
        final image = await PdfPageRenderer.render(page,
            options: PdfRenderOptions(
              dpi: 36,
              maxPixels: 30000000,
              fontFallback: fallbackBytes == null
                  ? null
                  : (request) async => fallbackBytes,
            ));
        rendered++;
        if (!image.report.isComplete) {
          incomplete++;
          note = ' incompleto: ${image.report}';
          image.report.unsupportedOperators.forEach((op, count) {
            unsupported[op] = (unsupported[op] ?? 0) + count;
          });
          for (final failure in image.report.fontFailures.values) {
            fontFailures[failure.name] = (fontFailures[failure.name] ?? 0) + 1;
          }
        }
      }
    } catch (e) {
      renderFailed++;
      failures['$name/render'] = '${e.runtimeType}: $e';
      note = ' RENDER-FALHOU ${e.runtimeType}';
    }
    await document.close();

    // --- compressão ----------------------------------------------------------
    var ratio = '';
    if (!onlyRender) {
      try {
        final result = await PdfCompressor.compress(bytes);
        // O resultado precisa reabrir: um compressor que produz lixo é pior
        // que um que não comprime.
        final reopened =
            await CraftPdfDocument.open(CraftPdfReader.fromBytes(result.bytes));
        final reopenedPages = await _countPages(reopened);
        await reopened.close();
        if (reopenedPages != pages) {
          compressFailed++;
          failures['$name/comprimir'] =
              'páginas mudaram: $pages -> $reopenedPages';
          ratio = ' COMPRESSAO PERDEU PAGINAS';
        } else {
          compressed++;
          final percent = (1 - result.bytes.length / bytes.length) * 100;
          ratio = ' ${percent.toStringAsFixed(1)}%';
        }
      } catch (e) {
        compressFailed++;
        failures['$name/comprimir'] = '${e.runtimeType}: $e';
        ratio = ' COMPRIMIR-FALHOU ${e.runtimeType}';
      }
    }

    print('ok ${name.padRight(48)} ${pages}p$ratio$note');
  }

  print('');
  print('=' * 78);
  print('arquivos              : ${files.length}');
  print('abriram               : $opened   (falha: $openFailed)');
  print('renderizaram          : $rendered (falha: $renderFailed)');
  print('  incompletos         : $incomplete');
  print('comprimiram e reabrem : $compressed (falha: $compressFailed)');

  if (unsupported.isNotEmpty) {
    final ranked = unsupported.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    print('');
    print('operadores não implementados, por frequência:');
    for (final entry in ranked.take(15)) {
      print('  ${entry.key.padRight(8)} ${entry.value}');
    }
  }

  if (fontFailures.isNotEmpty) {
    final ranked = fontFailures.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    print('');
    print('fontes recusadas, por motivo (contagem de fontes distintas):');
    for (final entry in ranked) {
      print('  ${entry.key.padRight(20)} ${entry.value}');
    }
  }

  if (failures.isNotEmpty) {
    print('');
    print('falhas:');
    final seen = <String, int>{};
    failures.forEach((where, what) {
      final kind = what.split(':').first;
      seen[kind] = (seen[kind] ?? 0) + 1;
    });
    seen.forEach((kind, count) => print('  ${count}x  $kind'));
    print('');
    failures.forEach((where, what) {
      final short = what.length > 110 ? '${what.substring(0, 110)}...' : what;
      print('  $where\n    $short');
    });
  }

  if (openFailed > 0 || renderFailed > 0 || compressFailed > 0) exitCode = 1;
}
