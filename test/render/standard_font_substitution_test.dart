import 'dart:convert';
import 'dart:typed_data';

import 'package:dgfx/dgfx.dart' show BLFontFace;
import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/io/resources/embedded_font_resources.dart';
import 'package:dpdf/src/render/glyph_source.dart';
import 'package:test/test.dart';

/// Uma página cujo texto usa a fonte `F1` declarada em [resources].
Future<PdfRenderedPage> _render(
  String content, {
  required PdfDictionary resources,
  double width = 320,
  double height = 100,
  bool useStandardFonts = true,
}) async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  page.pdfRepresentation()
    ..put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, width, height]))
    ..put(PdfName.contents,
        PdfStream.withBytes(Uint8List.fromList(latin1.encode(content)), 0))
    ..put(PdfName.resources, resources);
  await document.close();

  final reopened =
      await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
  try {
    return await PdfPageRenderer.render((await reopened.pageAt(1))!,
        options: PdfRenderOptions(dpi: 72, useStandardFonts: useStandardFonts));
  } finally {
    await reopened.close();
  }
}

/// Um dicionário `/Resources` com uma das catorze padrão sob o nome `F1`.
///
/// Nenhuma delas traz `/Widths` nem `/FontDescriptor`: é exatamente o que a
/// 9.6.2.2 permite, e o que obriga o leitor a conhecer métricas e contornos.
PdfDictionary _standardFont(
  String baseFont, {
  String? encoding,
  Map<int, String>? differences,
}) {
  final font = PdfDictionary()
    ..put(PdfName('Type'), PdfName('Font'))
    ..put(PdfName.subtype, PdfName('Type1'))
    ..put(PdfName.baseFont, PdfName(baseFont));

  if (differences != null) {
    final array = PdfArray();
    final codes = differences.keys.toList()..sort();
    for (final code in codes) {
      array.add(PdfNumber.fromInt(code));
      array.add(PdfName(differences[code]!));
    }
    final dictionary = PdfDictionary()
      ..put(PdfName('Type'), PdfName('Encoding'))
      ..put(PdfName('Differences'), array);
    if (encoding != null) {
      dictionary.put(PdfName('BaseEncoding'), PdfName(encoding));
    }
    font.put(PdfName('Encoding'), dictionary);
  } else if (encoding != null) {
    font.put(PdfName('Encoding'), PdfName(encoding));
  }

  return PdfDictionary()
    ..put(PdfName('Font'), PdfDictionary()..put(PdfName('F1'), font));
}

/// Quantos pixels ficaram mais escuros que o cinza médio.
int _inked(PdfRenderedPage page) {
  var count = 0;
  for (final pixel in page.pixels) {
    if ((pixel & 0xFF) < 128) count++;
  }
  return count;
}

/// A extensão horizontal da tinta, como (primeira coluna, última).
(int, int)? _inkExtent(PdfRenderedPage page) {
  int? left, right;
  for (var y = 0; y < page.height; y++) {
    for (var x = 0; x < page.width; x++) {
      if ((page.pixels[y * page.width + x] & 0xFF) >= 128) continue;
      if (left == null || x < left) left = x;
      if (right == null || x > right) right = x;
    }
  }
  return left == null ? null : (left, right!);
}

/// Pares código/nome que o AFM de [face] declara.
Map<int, String> _afmEncoding(String face) {
  final metrics = EmbeddedFontResources.metrics(face)!;
  final table = <int, String>{};
  for (final line in const LineSplitter().convert(latin1.decode(metrics))) {
    if (!line.startsWith('C ')) continue;
    final fields = <String, String>{};
    for (final field in line.split(';')) {
      final item = field.trim();
      final separator = item.indexOf(' ');
      if (separator > 0) {
        fields[item.substring(0, separator)] = item.substring(separator + 1);
      }
    }
    final code = int.parse(fields['C']!);
    if (code >= 0) table[code] = fields['N']!;
  }
  return table;
}

void main() {
  group('substituição pelas URW embutidas', () {
    test('desenha uma das catorze padrão em vez de deixar a página vazia',
        () async {
      final resources = _standardFont('Helvetica');
      const content = 'BT /F1 36 Tf 20 40 Td (Hamburg) Tj ET';

      final sem = await _render(content,
          resources: resources, useStandardFonts: false);
      final com = await _render(content, resources: resources);

      expect(sem.report.glyphsSkipped, greaterThan(0));
      expect(_inked(sem), isZero,
          reason: 'sem substituta não há contorno nenhum para desenhar');

      expect(com.report.glyphsSkipped, isZero);
      expect(_inked(com), greaterThan(200),
          reason: 'sete glifos a 36pt têm de deixar tinta de verdade');
    });

    test('o relatório nomeia a fonte trocada, em vez de escondê-la', () async {
      final page = await _render('BT /F1 24 Tf 20 40 Td (Hamburg) Tj ET',
          resources: _standardFont('Times-BoldItalic'));

      expect(page.report.fontsSubstituted, equals(['Times-BoldItalic']));
      expect(page.report.toString(), contains('substituted'));
      expect(page.report.toString(), contains('Times-BoldItalic'));
    });

    test('sem substituição o relatório não acusa troca nenhuma', () async {
      final page = await _render('BT /F1 24 Tf 20 40 Td (Hamburg) Tj ET',
          resources: _standardFont('Helvetica'), useStandardFonts: false);

      expect(page.report.fontsSubstituted, isEmpty);
      expect(page.report.fontFailures['F1'],
          equals(PdfGlyphFailure.notEmbedded));
    });

    test('escolhe o corte pedido: negrito, itálico e monoespaçado', () {
      String? face(String baseFont, {int flags = 0}) => standardFaceName(
          PdfFontRequest(baseFont: baseFont, flags: flags, composite: false));

      expect(face('Helvetica'), 'NimbusSans-Regular');
      expect(face('Helvetica-Bold'), 'NimbusSans-Bold');
      expect(face('Helvetica-Oblique'), 'NimbusSans-Oblique');
      expect(face('Helvetica-BoldOblique'), 'NimbusSans-BoldOblique');
      expect(face('Times-Roman'), 'NimbusRoman-Regular');
      expect(face('Times-BoldItalic'), 'NimbusRoman-BoldItalic');
      expect(face('Courier-Bold'), 'NimbusMonoPS-Bold');
      expect(face('Symbol'), 'StandardSymbolsPS');
      expect(face('ZapfDingbats'), 'D050000L');

      // Os apelidos que produtores usam no lugar dos nomes canônicos.
      expect(face('ABCDEF+ArialMT'), 'NimbusSans-Regular');
      expect(face('Arial,Bold'), 'NimbusSans-Bold');
      expect(face('TimesNewRomanPSMT'), 'NimbusRoman-Regular');
      expect(face('CourierNew'), 'NimbusMonoPS-Regular');

      // Uma fonte qualquer não embutida cai no desenho que o `/Flags` pede:
      // bit 1 é monoespaçada, bit 2 serifada, bit 19 negrito.
      expect(face('Whatever'), 'NimbusSans-Regular');
      expect(face('Whatever', flags: 2), 'NimbusRoman-Regular');
      expect(face('Whatever', flags: 1), 'NimbusMonoPS-Regular');
      expect(face('Whatever', flags: 0x40002), 'NimbusRoman-Bold');
    });

    test('não substitui uma fonte simbólica desconhecida', () {
      // Bit 3 do `/Flags`: o conjunto de glifos é próprio da fonte. Desenhar
      // letras no lugar dos símbolos seria pior do que não desenhar.
      expect(
          standardFaceName(const PdfFontRequest(
              baseFont: 'Wingdings', flags: 4, composite: false)),
          isNull);
    });

    test('não substitui uma fonte composta, cujo CID não significa nada fora '
        'do programa original', () {
      expect(
          standardFaceName(const PdfFontRequest(
              baseFont: 'Helvetica', flags: 0, composite: true)),
          isNull);
    });

    test('Symbol e ZapfDingbats recebem a URW com o conjunto de glifos certo',
        () async {
      // Não basta que algo seja desenhado: o glifo tem de ser o que o código
      // designa. O AFM de cada face diz qual nome cada código tem, e a URW
      // resolve os dois caminhos que o renderizador usa — o nome do glifo e a
      // `cmap` — para o mesmo índice.
      for (final pair in const [
        ('Symbol', 'StandardSymbolsPS'),
        ('ZapfDingbats', 'D050000L'),
      ]) {
        final request = PdfFontRequest(
            baseFont: pair.$1, flags: 4, composite: false);
        expect(standardFaceName(request), pair.$2);

        final bytes = await standardFontFallback()!(request);
        final face = BLFontFace.parse(bytes!);
        final encoding = _afmEncoding(pair.$1);
        expect(encoding.length, greaterThan(180));

        encoding.forEach((code, name) {
          final byName = face.glyphIdForName(name);
          expect(byName, isNotNull,
              reason: '${pair.$2} não tem o glifo $name de ${pair.$1}');
          expect(face.mapCodePoint(code), equals(byName),
              reason: 'código $code de ${pair.$1} deveria selecionar $name');
        });
      }
    });

    test('a linha de Symbol sai desenhada, não pulada', () async {
      final page = await _render(
          'BT /F1 24 Tf 20 40 Td (abgdez) Tj ET',
          resources: _standardFont('Symbol'));

      expect(page.report.glyphsSkipped, isZero);
      expect(page.report.fontsSubstituted, equals(['Symbol']));
      expect(_inked(page), greaterThan(100),
          reason: 'seis letras gregas a 24pt deixam tinta');
    });

    test('a linha de ZapfDingbats sai desenhada, não pulada', () async {
      final page = await _render(
          'BT /F1 24 Tf 20 40 Td (34567) Tj ET',
          resources: _standardFont('ZapfDingbats'));

      expect(page.report.glyphsSkipped, isZero);
      expect(page.report.fontsSubstituted, equals(['ZapfDingbats']));
      expect(_inked(page), greaterThan(100));
    });
  });

  group('métricas das catorze sem /Widths', () {
    Future<PdfGlyphSource> source(String baseFont,
        {String? encoding, Map<int, String>? differences}) async {
      final resolved = await PdfGlyphSource.resolve(
          _standardFont(baseFont,
              encoding: encoding, differences: differences),
          'F1');
      return resolved!;
    }

    test('WinAnsiEncoding mede os acentos pelo nome do glifo, não pelo código',
        () async {
      // 0xE7 é `ccedilla` em WinAnsi e `lslash` em StandardEncoding. No AFM o
      // ccedilla aparece com `C -1`: procurar por código devolve nada, o
      // avanço vira zero e os glifos acentuados se empilham num ponto só.
      final font = await source('Helvetica', encoding: 'WinAnsiEncoding');

      expect(font.width(0xE7) * 1000, closeTo(500, 0.01), reason: 'ccedilla');
      expect(font.width(0xE3) * 1000, closeTo(556, 0.01), reason: 'atilde');
      expect(font.width(0xE9) * 1000, closeTo(556, 0.01), reason: 'eacute');
      expect(font.width(0x41) * 1000, closeTo(667, 0.01), reason: 'A');
    });

    test('MacRomanEncoding dá outro byte ao mesmo glifo, e a largura segue',
        () async {
      // Em MacRoman o ccedilla é 0x8D e o atilde 0x8B; em WinAnsi seriam
      // 0xE7 e 0xE3. É o mesmo glifo, com a mesma largura, em bytes
      // diferentes — o que só sai certo consultando por nome.
      final font = await source('Helvetica', encoding: 'MacRomanEncoding');

      expect(font.width(0x8D) * 1000, closeTo(500, 0.01), reason: 'ccedilla');
      expect(font.width(0x8B) * 1000, closeTo(556, 0.01), reason: 'atilde');
    });

    test('/Differences vence a codificação base', () async {
      final font = await source('Helvetica',
          encoding: 'WinAnsiEncoding', differences: {0x41: 'ccedilla'});

      expect(font.width(0x41) * 1000, closeTo(500, 0.01),
          reason: 'o código 0x41 foi remapeado para ccedilla');
      expect(font.width(0xE7) * 1000, closeTo(500, 0.01),
          reason: 'o resto da base continua valendo');
    });

    test('sem /Encoding a base é a codificação embutida da fonte', () async {
      final font = await source('Helvetica');

      expect(font.width(0x41) * 1000, closeTo(667, 0.01), reason: 'A');
      expect(font.width(0x20) * 1000, closeTo(278, 0.01), reason: 'space');
    });

    test('Symbol e ZapfDingbats medem pela própria codificação', () async {
      // A 9.6.6.2 diz que essas duas trazem codificação embutida: o código do
      // AFM é o byte que o documento usa, qualquer que seja o `/Encoding`.
      final symbol = await source('Symbol', encoding: 'WinAnsiEncoding');
      expect(symbol.width(0x61) * 1000, closeTo(631, 0.01), reason: 'alpha');

      final dingbats = await source('ZapfDingbats');
      expect(dingbats.width(0x61) * 1000, closeTo(789, 0.01), reason: 'a60');
    });

    test('uma linha acentuada ocupa a largura que o AFM prevê', () async {
      // O teste que pega o avanço zerado de ponta a ponta: com as larguras
      // erradas os glifos se sobrepõem e a linha encolhe.
      const text = 'ação coração até';
      final bytes = PdfSimpleEncoding.encode('WinAnsiEncoding', text);
      final escaped = StringBuffer();
      for (final byte in bytes) {
        if (byte == 0x28 || byte == 0x29 || byte == 0x5C) escaped.write(r'\');
        escaped.writeCharCode(byte);
      }

      final page = await _render(
        'BT /F1 20 Tf 10 40 Td ($escaped) Tj ET',
        resources: _standardFont('Helvetica', encoding: 'WinAnsiEncoding'),
        width: 400,
      );
      final extent = _inkExtent(page);
      expect(extent, isNotNull);

      final predicted = PdfStandardFontMetrics.textWidth(
          'Helvetica', 'WinAnsiEncoding', text, 20);
      final drawn = extent!.$2 - extent.$1;
      // O avanço do último glifo passa da sua tinta, então o desenho é sempre
      // um pouco mais estreito que a soma das larguras.
      expect(drawn, greaterThan(predicted * 0.9),
          reason: 'largura desenhada $drawn contra $predicted previstos');
      expect(drawn, lessThan(predicted * 1.05));
      expect(page.report.glyphsSkipped, isZero);
    });
  });
}
