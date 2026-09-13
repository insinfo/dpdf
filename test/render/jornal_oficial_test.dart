import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// Capas do Jornal Oficial de Rio das Ostras, produzidas por uma ferramenta
/// comercial de diagramação.
///
/// Todo o resto do corpus de teste deste pacote foi escrito pelo próprio
/// pacote, e um corpus que nós geramos só exercita as construções que nós
/// escolhemos emitir. Estes arquivos trazem subconjuntos TrueType embutidos,
/// fontes Type0/Identity-H, dicionários de recursos que reaproveitam nomes
/// curtos entre Form XObjects, e imagens desenhadas em escala reduzida.
///
/// O que este teste vigia são os **contadores de trabalho não feito**. Num
/// documento estrangeiro são eles que se mexem primeiro: glifo pulado, imagem
/// pulada, operador desconhecido. Foi assim que apareceram, hoje, fontes Type 3
/// ausentes do renderizador e imagens recusadas por codec.
///
/// O que este teste **não** pega: glifo errado desenhado no lugar do certo.
/// Nada é "pulado" ali, e a tinta da página mal se move. Esse defeito — a
/// fonte resolvida pelo nome do recurso, que estes mesmos arquivos expuseram —
/// está travado em `font_resource_name_test.dart`, que monta a colisão
/// diretamente. Medi antes de decidir: comparar pixel a pixel com a capa
/// publicada pelo órgão movia a divergência de 2,50 % para 3,24 % com o bug
/// presente, e o pior bloco de 32x32 não se movia. Um oráculo que não separa
/// certo de errado não é oráculo.
///
/// Procedência e licença: `test/assets/jornal-oficial/NOTICE.md`.
void main() {
  final pasta = Directory('test/assets/jornal-oficial');
  final edicoes = pasta.existsSync()
      ? (pasta
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'))
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort())
      : <String>[];

  group('capas do Jornal Oficial', () {
    for (final nome in edicoes) {
      test('$nome desenha a primeira página inteira', () async {
        final bytes =
            Uint8List.fromList(File('${pasta.path}/$nome').readAsBytesSync());
        final doc = await PdfDocument.open(PdfReader.fromBytes(bytes));
        try {
          final pagina = await doc.pageAt(1);
          expect(pagina, isNotNull, reason: 'documento sem primeira página');

          final r = await PdfPageRenderer.render(pagina!,
              options: const PdfRenderOptions(dpi: 72));

          expect(r.report.glyphsSkipped, 0,
              reason: 'glifo não desenhado: ${r.report}');
          expect(r.report.imagesSkipped, 0,
              reason: 'imagem não desenhada: ${r.report}');
          expect(r.report.unsupportedOperators, isEmpty,
              reason: 'operador não interpretado: ${r.report}');

          var tinta = 0.0;
          for (final c in r.pixels) {
            final cinza = ((c >> 16 & 0xFF) + (c >> 8 & 0xFF) + (c & 0xFF)) / 3;
            tinta += (255 - cinza) / 255;
          }
          final fracao = tinta / (r.width * r.height);
          // Uma capa é uma fotografia de página inteira com faixas de cor por
          // cima. Perto de zero significa página em branco; perto de um,
          // uma forma gigante pintada por cima de tudo.
          expect(fracao, greaterThan(0.10), reason: 'a capa saiu quase vazia');
          expect(fracao, lessThan(0.95),
              reason: 'a capa saiu quase toda preta');
        } finally {
          await doc.close();
        }
      });
    }

    test('renderizar duas vezes dá exatamente os mesmos pixels', () async {
      final nome = edicoes.first;
      final bytes =
          Uint8List.fromList(File('${pasta.path}/$nome').readAsBytesSync());
      Future<PdfRenderedPage> render() async {
        final doc = await PdfDocument.open(PdfReader.fromBytes(bytes));
        try {
          return await PdfPageRenderer.render((await doc.pageAt(1))!,
              options: const PdfRenderOptions(dpi: 72));
        } finally {
          await doc.close();
        }
      }

      final a = await render();
      final b = await render();
      expect(b.pixels, orderedEquals(a.pixels));
    });
  },
      skip: edicoes.isEmpty
          ? 'test/assets/jornal-oficial ausente: o diretório fica fora do '
              'pacote publicado, então este teste só roda a partir do '
              'repositório.'
          : null);
}
