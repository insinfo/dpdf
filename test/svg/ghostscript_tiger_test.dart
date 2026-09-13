import 'dart:io';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// O Ghostscript Tiger é a imagem de esforço clássica do PostScript e do PDF:
/// centenas de caminhos preenchidos, muitos deles também traçados, com
/// `viewBox`, grupos e transformações aninhadas. É o desenho com que geradores
/// de PDF são comparados há décadas, e não foi produzido por este projeto —
/// que é justamente o ponto cego de um corpus gerado por nós mesmos.
///
/// Licença: AGPL, **não** domínio público como as demais ilustrações. Veja
/// `test/assets/ghostscript-tiger/NOTICE.md`; o diretório é versionado mas
/// fica fora do pacote publicado.
void main() {
  final origem = File('test/assets/ghostscript-tiger/ghostscript-tiger.svg');

  group('Ghostscript Tiger', () {
    late String svg;
    late PdfRenderedPage pagina;

    setUpAll(() async {
      svg = origem.readAsStringSync();
      final bytes = await SvgConverter.convertToBytes(svg);
      final doc = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        pagina = await PdfPageRenderer.render((await doc.pageAt(1))!,
            options: const PdfRenderOptions(dpi: 72));
      } finally {
        await doc.close();
      }
    });

    test('a conversão não pula nada e a página não sai em branco', () {
      // `isComplete` é o que separa "desenhou" de "desenhou tudo": um caminho
      // pulado não aparece em lugar nenhum senão aqui.
      expect(pagina.report.unsupportedOperators, isEmpty,
          reason: 'operador não suportado no fluxo que nós mesmos geramos');
      expect(pagina.report.glyphsSkipped, 0);
      expect(pagina.report.imagesSkipped, 0);

      var tinta = 0.0;
      for (final c in pagina.pixels) {
        final cinza = ((c >> 16 & 0xFF) + (c >> 8 & 0xFF) + (c & 0xFF)) / 3;
        tinta += (255 - cinza) / 255;
      }
      // O desenho ocupa cerca de um terço da área; qualquer coisa perto de
      // zero significa que a conversão engoliu o conteúdo.
      final area = pagina.width * pagina.height;
      expect(tinta / area, greaterThan(0.15),
          reason: 'a página saiu quase vazia');
      expect(tinta / area, lessThan(0.60),
          reason: 'a página saiu quase toda preenchida, o que indicaria um '
              'caminho gigante pintado por cima do resto');
    });

    test('as cores características do desenho aparecem', () {
      // Laranja do pelo, preto das listras, branco do focinho e verde dos
      // olhos. Conferir cor, e não só cobertura, é o que pega uma conversão
      // que desenha as formas certas com o preenchimento errado.
      var laranja = 0, preto = 0, branco = 0;
      for (final c in pagina.pixels) {
        final r = c >> 16 & 0xFF, g = c >> 8 & 0xFF, b = c & 0xFF;
        if (r > 150 && g > 60 && g < 150 && b < 70) laranja++;
        if (r < 45 && g < 45 && b < 45) preto++;
        if (r > 245 && g > 245 && b > 245) branco++;
      }
      expect(laranja, greaterThan(2000), reason: 'sumiu o laranja do pelo');
      expect(preto, greaterThan(2000), reason: 'sumiram as listras pretas');
      expect(branco, greaterThan(2000), reason: 'sumiu o fundo branco');
    });

    test('converter duas vezes desenha exatamente o mesmo', () async {
      // Saída determinística: sem isto, comparar renderizações entre versões
      // não significa nada.
      //
      // A comparação é sobre os PIXELS, e não sobre os bytes do arquivo. Os
      // dois PDFs diferem de propósito no `/ID` do trailer, que a 14.4 manda
      // ser único por documento — asseverar igualdade byte a byte exigiria
      // quebrar essa regra.
      final outra = await SvgConverter.convertToBytes(svg);
      final doc = await PdfDocument.open(PdfReader.fromBytes(outra));
      late PdfRenderedPage segunda;
      try {
        segunda = await PdfPageRenderer.render((await doc.pageAt(1))!,
            options: const PdfRenderOptions(dpi: 72));
      } finally {
        await doc.close();
      }
      expect(segunda.width, pagina.width);
      expect(segunda.height, pagina.height);
      expect(segunda.pixels, orderedEquals(pagina.pixels));
    });
  },
      skip: origem.existsSync()
          ? null
          : 'test/assets/ghostscript-tiger/ghostscript-tiger.svg ausente: o '
              'diretório fica fora do pacote publicado, então este teste só '
              'roda a partir do repositório.');
}
