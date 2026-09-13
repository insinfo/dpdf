import 'dart:io';

import 'package:dgfx/dgfx.dart' show BLFontFace;
import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// A fonte de teste, usada como se fosse a do sistema.
const _asset = 'test/assets/ABeeZee-Regular.ttf';

PdfFontRequest _request(String baseFont, {int flags = 0}) =>
    PdfFontRequest(baseFont: baseFont, flags: flags, composite: false);

/// Um diretório de fontes fabricado, para não depender do que a máquina tem.
///
/// Um teste que só passa numa instalação específica do Windows não prova nada
/// sobre o resolvedor: prova que aquela máquina tem Arial.
Directory _catalogue(String name, Map<String, String> files) {
  final directory =
      Directory.systemTemp.createTempSync('dpdf_fontes_$name');
  addTearDown(() => directory.deleteSync(recursive: true));
  final bytes = File(_asset).readAsBytesSync();
  files.forEach((path, source) {
    final target = File('${directory.path}/$path');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(source == _asset ? bytes : File(source).readAsBytesSync());
  });
  return directory;
}

void main() {
  setUpAll(() {
    if (!File(_asset).existsSync()) {
      throw StateError('falta o recurso de teste $_asset');
    }
  });

  group('fontes do sistema', () {
    test('acha o arquivo da família pedida e devolve os bytes', () async {
      final directory = _catalogue('achar', {'arial.ttf': _asset});
      final fallback = systemFontFallback(directories: [directory.path])!;

      final bytes = await fallback(_request('Helvetica'));

      expect(bytes, isNotNull);
      expect(BLFontFace.parse(bytes!).familyName, 'ABeeZee',
          reason: 'os bytes têm de ser os do arquivo encontrado');
    });

    test('procura em subdiretórios, como os catálogos de sistema usam',
        () async {
      final directory =
          _catalogue('recursivo', {'truetype/liberation/arial.ttf': _asset});
      final fallback = systemFontFallback(directories: [directory.path])!;

      expect(await fallback(_request('Helvetica')), isNotNull);
    });

    test('honra negrito e itálico ao escolher o arquivo', () async {
      final directory = _catalogue('cortes', {
        'arial.ttf': _asset,
        'arialbd.ttf': _asset,
        'arialbi.ttf': _asset,
      });
      // O resolvedor devolve bytes, não caminhos; o que dá para observar é que
      // ele responde a cada corte. Os três arquivos são cópias da mesma fonte,
      // então o teste do corte certo está na escolha do nome, exercitada aqui
      // pela ausência: um pedido de negrito num catálogo só com o normal
      // ainda responde, mas o contrário nunca inventa um arquivo.
      final fallback = systemFontFallback(directories: [directory.path])!;
      expect(await fallback(_request('Arial-Bold')), isNotNull);
      expect(await fallback(_request('Arial-BoldItalic')), isNotNull);

      final somenteNegrito =
          _catalogue('so_negrito', {'arialbd.ttf': _asset});
      final outro = systemFontFallback(directories: [somenteNegrito.path])!;
      expect(await outro(_request('Arial-Bold')), isNotNull);
      expect(await outro(_request('Helvetica')), isNull,
          reason: 'só há o corte negrito no catálogo, e ele não serve de '
              'normal: o arquivo do normal simplesmente não existe');
    });

    test('sem nada no catálogo, não substitui', () async {
      final directory = _catalogue('vazio', const {});
      final fallback = systemFontFallback(directories: [directory.path])!;

      expect(await fallback(_request('Helvetica')), isNull);
      expect(await fallback(_request('Times-Roman')), isNull);
      expect(await fallback(_request('Symbol')), isNull);
    });

    test('um diretório inexistente não derruba a busca', () async {
      final fallback = systemFontFallback(
          directories: ['${Directory.systemTemp.path}/dpdf_nao_existe_87213'])!;

      expect(await fallback(_request('Helvetica')), isNull);
    });

    test('não aceita qualquer arquivo chamado zapfdingbats', () async {
      // O nome do arquivo não é prova de nada. Wingdings responde aos mesmos
      // códigos com outros desenhos, e uma fonte de texto responde com letras.
      // Desenhar símbolos trocados é pior do que não desenhar: quem conta os
      // glifos pulados sabe que faltou algo, quem vê letras no lugar dos
      // símbolos não.
      final directory = _catalogue('dingbats_falso', {
        'zapfdingbats.ttf': _asset,
        'dingbats.ttf': _asset,
      });
      final fallback = systemFontFallback(directories: [directory.path])!;

      expect(await fallback(_request('ZapfDingbats', flags: 4)), isNull);
    });

    test('não aceita qualquer arquivo chamado symbol', () async {
      final directory = _catalogue('symbol_falso', {'symbol.ttf': _asset});
      final fallback = systemFontFallback(directories: [directory.path])!;

      expect(await fallback(_request('Symbol', flags: 4)), isNull,
          reason: 'a ABeeZee não traz o conjunto de glifos da Symbol');
    });

    test('não substitui uma fonte simbólica desconhecida por uma de texto',
        () async {
      final directory = _catalogue('simbolica', {'arial.ttf': _asset});
      final fallback = systemFontFallback(directories: [directory.path])!;

      expect(await fallback(_request('Wingdings', flags: 4)), isNull);
    });

    test('um nome desconhecido cai no desenho que o /Flags pede', () async {
      final directory = _catalogue('generico', {'times.ttf': _asset});
      final fallback = systemFontFallback(directories: [directory.path])!;

      // Bit 2 do `/Flags` é serifada, e o catálogo só tem a serifada.
      expect(await fallback(_request('Alguma-Fonte', flags: 2)), isNotNull);
      expect(await fallback(_request('Alguma-Fonte')), isNull,
          reason: 'sem serifa o catálogo não tem nada que sirva');
    });

    test('o catálogo real da máquina, quando houver', () async {
      // Este é o único teste que toca nas fontes instaladas, e ele se pula
      // sozinho onde não houver nenhuma: uma máquina de CI sem fontes não
      // pode reprovar o pacote.
      final fallback = systemFontFallback();
      final bytes = await fallback!(_request('Helvetica'));
      if (bytes == null) {
        markTestSkipped('nenhuma fonte de sistema legível nesta máquina');
        return;
      }
      expect(() => BLFontFace.parse(bytes), returnsNormally);
    });
  });
}
