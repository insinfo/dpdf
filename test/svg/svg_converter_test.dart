import 'dart:typed_data';

import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/svg/svg_converter.dart';
import 'package:test/test.dart';

/// Desenha [svg] num canvas solto e devolve o fluxo de conteúdo gerado.
///
/// Um canvas sem documento é suficiente para tudo que este módulo emite e
/// deixa o resultado legível: os operadores aparecem exatamente na ordem em
/// que foram escritos, sem passar por objetos indiretos.
Future<String> _render(String svg, {Rectangle? viewport}) async {
  final stream = PdfStream();
  final canvas = PdfCanvas(stream, null, null);
  await SvgConverter.drawOnCanvas(svg, canvas, viewport: viewport);
  final bytes = await stream.getBytes();
  return String.fromCharCodes(bytes!);
}

int _count(String content, String operator) =>
    operator.allMatches(content).length;

void main() {
  group('SvgConverter no fluxo de conteúdo', () {
    test('inverte o eixo Y e recorta o viewport antes de desenhar', () async {
      // 100 unidades de usuário = 75 pt, e a origem do SVG passa a ser o
      // canto superior esquerdo do viewport.
      final content =
          await _render('<svg width="100" height="100"><rect x="10" y="20" '
              'width="30" height="40"/></svg>');

      expect(content, contains('1 0 0 -1 0 75 cm\n'));
      expect(content, contains('0 0 75 75 re\nW\n'));
    });

    test('emite o retângulo com as coordenadas convertidas para pontos',
        () async {
      final content =
          await _render('<svg width="100" height="100"><rect x="10" y="20" '
              'width="30" height="40" fill="#ff0000"/></svg>');

      expect(content, contains('1 0 0 rg\n'));
      expect(content, contains('7.5 15 22.5 30 re\n'));
      expect(content, contains('f\n'));
    });

    test('posiciona o desenho no viewport informado', () async {
      final content = await _render(
          '<svg width="100" height="100"><rect width="10" height="10"/></svg>',
          viewport: Rectangle(100, 200, 60, 40));

      // A inversão leva a origem local ao topo do retângulo pedido; daí em
      // diante o recorte e o desenho já falam em coordenadas locais.
      expect(content, contains('1 0 0 -1 100 240 cm\n'));
      expect(content, contains('0 0 60 40 re\nW\n'));
    });

    test('aplica transform de translação ao grupo inteiro', () async {
      final content = await _render('<svg width="100" height="100">'
          '<g transform="translate(10,20)">'
          '<rect width="4" height="4" fill="none" stroke="black"/>'
          '</g></svg>');

      // A translação também é medida em unidades de usuário: 10px = 7,5pt.
      expect(content, contains('1 0 0 1 7.5 15 cm\n'));
      // O retângulo continua nas suas próprias coordenadas; quem o move é o cm.
      expect(content, contains('0 0 3 3 re\n'));
    });

    test('aplica transform de escala no próprio elemento', () async {
      final content = await _render('<svg width="100" height="100">'
          '<rect width="4" height="4" transform="scale(2)"/></svg>');

      expect(content, contains('2 0 0 2 0 0 cm\n'));
      expect(content, contains('0 0 3 3 re\n'));
    });

    test('viewBox reescala o sistema de coordenadas do usuário', () async {
      // 200x100 unidades mapeadas num viewport de 75x37,5 pt: fator 0,5.
      final content = await _render('<svg width="100" height="50" '
          'viewBox="0 0 200 100"><rect width="200" height="100"/></svg>');

      expect(content, contains('0.5 0 0 0.5 0 0 cm\n'));
      expect(content, contains('0 0 150 75 re\n'));
    });

    test('preserveAspectRatio centra o desenho na sobra do viewport', () async {
      // Viewport 75x75 e viewBox 150x75 (já em pontos): a escala uniforme é
      // 0,5 e sobram 37,5 pt de altura, centrados como 18,75 de cada lado.
      final content = await _render('<svg width="100" height="100" '
          'viewBox="0 0 200 100"><rect width="10" height="10"/></svg>');

      expect(content, contains('1 0 0 1 0 18.75 cm\n'));
      expect(content, contains('0.5 0 0 0.5 0 0 cm\n'));
    });

    test('sem width e height o tamanho vem do viewBox', () async {
      // `width`/`height` ausentes valem 100%, e a base do percentual é o
      // próprio viewBox: 200x100 unidades = 150x75 pt, sem reescala.
      final content = await _render(
          '<svg viewBox="0 0 200 100"><rect width="200" height="100"/></svg>');

      expect(content, contains('1 0 0 -1 0 75 cm\n'));
      expect(content, contains('0 0 150 75 re\n'));
      expect(content, isNot(contains(' 0 0 cm\n')));
    });

    test('svg aninhado ganha viewport e recorte próprios', () async {
      final content = await _render('<svg width="40" height="40">'
          '<svg x="10" y="10" width="20" height="20" viewBox="0 0 40 40">'
          '<rect width="40" height="40"/></svg></svg>');

      expect(content, contains('7.5 7.5 15 15 re\nW\n'));
      expect(content, contains('1 0 0 1 7.5 7.5 cm\n'));
      expect(content, contains('0.5 0 0 0.5 0 0 cm\n'));
    });

    test('círculo começa no ponto mais à direita e usa quatro cúbicas',
        () async {
      final content = await _render(
          '<svg width="100" height="100"><circle cx="20" cy="20" r="10"/></svg>');

      // (cx + r, cy) em pontos: (30, 20) * 0,75.
      expect(content, contains('22.5 15 m\n'));
      expect(_count(content, ' c\n'), 4);
    });

    test('elipse respeita raios diferentes por eixo', () async {
      final content = await _render('<svg width="100" height="100">'
          '<ellipse cx="20" cy="20" rx="10" ry="4"/></svg>');

      expect(content, contains('22.5 15 m\n'));
      // Extremo inferior da elipse: cy + ry = 24 unidades = 18 pt.
      expect(content, contains('15 18 c\n'));
    });

    test('linha traça e nunca preenche', () async {
      final content = await _render('<svg width="100" height="100">'
          '<line x1="10" y1="10" x2="30" y2="40" stroke="blue" '
          'stroke-width="2"/></svg>');

      expect(content, contains('0 0 1 RG\n'));
      expect(content, contains('1.5 w\n'));
      expect(content, contains('7.5 7.5 m\n'));
      expect(content, contains('22.5 30 l\n'));
      expect(content, contains('S\n'));
      expect(_count(content, '\nf\n'), 0);
    });

    test('polígono fecha o contorno e a polilinha não', () async {
      final polygon = await _render('<svg width="100" height="100">'
          '<polygon points="0,0 10,0 10,10"/></svg>');
      final polyline = await _render('<svg width="100" height="100">'
          '<polyline points="0,0 10,0 10,10" fill="none" stroke="black"/></svg>');

      expect(polygon, contains('7.5 0 l\n'));
      expect(polygon, contains('7.5 7.5 l\n'));
      expect(polygon, contains('h\n'));
      expect(polyline, isNot(contains('h\n')));
    });

    test('path relativo com curva vira operadores absolutos', () async {
      final content = await _render('<svg width="100" height="100">'
          '<path d="m10 10 c0 0 10 10 20 20" fill="none" stroke="black"/></svg>');

      expect(content, contains('7.5 7.5 m\n'));
      // Controles (10,10) e (20,20) e destino (30,30), em pontos.
      expect(content, contains('7.5 7.5 15 15 22.5 22.5 c\n'));
    });

    test('retângulo arredondado emite quatro cúbicas e fecha', () async {
      final content = await _render(
          '<svg width="100" height="100"><rect width="8" height="8" rx="2"/></svg>');

      expect(content, contains('1.5 0 m\n'));
      expect(_count(content, ' c\n'), 4);
      expect(content, contains('h\n'));
    });

    test('fill herdado do grupo e style inline vencendo o atributo', () async {
      final content = await _render('<svg width="100" height="100">'
          '<g fill="#00ff00">'
          '<rect width="4" height="4"/>'
          '<rect width="4" height="4" fill="red" style="fill:#0000ff"/>'
          '</g></svg>');

      expect(content, contains('0 1 0 rg\n'));
      expect(content, contains('0 0 1 rg\n'));
      expect(content, isNot(contains('1 0 0 rg\n')));
    });

    test('aplica regras de style por tag, classe e id com cascata', () async {
      final content = await _render('''
        <svg width="40" height="20">
          <style>
            rect { fill: red; }
            .accent { fill: blue; stroke: black; }
            #chosen { fill: #0f0; }
          </style>
          <rect class="accent" width="5" height="5"/>
          <rect id="chosen" class="accent" x="10" width="5" height="5"/>
        </svg>
      ''');

      expect(_count(content, '0 0 1 rg\n'), 1);
      expect(_count(content, '0 1 0 rg\n'), 1);
      expect(_count(content, '0 0 0 RG\n'), 2);
    });

    test('style inline vence regra de id e comentários CSS são ignorados',
        () async {
      final content = await _render('''
        <svg width="20" height="20">
          <style>/* fill: red */ #box { fill: blue; }</style>
          <rect id="box" style="fill:yellow" width="5" height="5"/>
        </svg>
      ''');

      expect(content, contains('1 1 0 rg\n'));
      expect(content, isNot(contains('0 0 1 rg\n')));
    });

    test('use instancia geometria de defs e aplica x e y', () async {
      final content = await _render('''
        <svg width="40" height="20">
          <defs><rect id="tile" width="4" height="6" fill="red"/></defs>
          <use href="#tile" x="10" y="5"/>
        </svg>
      ''');

      expect(content, contains('1 0 0 1 7.5 3.75 cm\n'));
      expect(content, contains('0 0 3 4.5 re\n'));
      expect(_count(content, '0 0 3 4.5 re\n'), 1,
          reason: 'a definição não pode vazar no ponto em que foi declarada');
    });

    test('use aceita xlink:href e interrompe referência circular', () async {
      final content = await _render('''
        <svg width="20" height="20" xmlns:xlink="http://www.w3.org/1999/xlink">
          <defs>
            <g id="cycle"><circle r="2"/><use xlink:href="#cycle"/></g>
          </defs>
          <use xlink:href="#cycle"/>
        </svg>
      ''');

      expect(_count(content, ' c\n'), 4,
          reason: 'um círculo tem quatro cúbicas e só pode sair uma vez');
    });

    test('aceita cor nomeada, hexadecimal curto e rgb percentual', () async {
      final named = await _render(
          '<svg width="20" height="20"><rect width="4" height="4" fill="yellow"/></svg>');
      final short = await _render(
          '<svg width="20" height="20"><rect width="4" height="4" fill="#0f0"/></svg>');
      final percent = await _render('<svg width="20" height="20">'
          '<rect width="4" height="4" fill="rgb(100%, 0%, 50%)"/></svg>');

      expect(named, contains('1 1 0 rg\n'));
      expect(short, contains('0 1 0 rg\n'));
      expect(percent, contains('1 0 0.5 rg\n'));
    });

    test('cor ininteligível recai em preto sem interromper o desenho',
        () async {
      final content = await _render('<svg width="20" height="20">'
          '<rect width="4" height="4" fill="not-a-color"/></svg>');

      expect(content, contains('0 0 0 rg\n'));
      expect(content, contains('0 0 3 3 re\n'));
    });

    test('regra de preenchimento par-ímpar usa o operador correspondente',
        () async {
      final content = await _render('<svg width="100" height="100">'
          '<path d="M0 0 L10 0 L10 10 Z" fill-rule="evenodd"/></svg>');

      expect(content, contains('f*\n'));
    });

    test('elementos ocultos não chegam ao fluxo', () async {
      final content = await _render('<svg width="100" height="100">'
          '<rect width="4" height="4" style="display:none"/>'
          '<rect width="4" height="4" visibility="hidden"/></svg>');

      expect(content, isNot(contains(' re\nW\nn\nq\n0 0 0 rg')));
      expect(_count(content, '0 0 3 3 re'), 0);
    });

    test('elementos ainda não suportados são ignorados sem quebrar o resto',
        () async {
      final content = await _render('<svg width="100" height="100">'
          '<text x="1" y="2">oi</text>'
          '<use href="#nada"/>'
          '<rect width="4" height="4"/></svg>');

      expect(content, contains('0 0 3 3 re\n'));
    });

    test('desenha o mesmo SVG mesmo declarado com prólogo XML', () async {
      final content = await _render('<?xml version="1.0" encoding="UTF-8"?>\n'
          '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">'
          '<rect width="4" height="4"/></svg>');

      expect(content, contains('0 0 3 3 re\n'));
    });
  });

  group('SvgConverter em documento', () {
    test('gera uma página do tamanho intrínseco do desenho', () async {
      final bytes = await SvgConverter.convertToBytes(
          '<svg width="100" height="60"><rect x="10" y="20" width="30" '
          'height="40" fill="#ff0000"/></svg>');

      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        expect(document.pageTotal(), 1);
        final page = (await document.pageAt(1))!;
        final bounds = await page.mediaBounds();
        expect(bounds.getWidth(), closeTo(75, 1e-9));
        expect(bounds.getHeight(), closeTo(45, 1e-9));

        final content = String.fromCharCodes(await page.contentPayload());
        expect(content, contains('1 0 0 -1 0 45 cm'));
        expect(content, contains('7.5 15 22.5 30 re'));
        expect(content, contains('1 0 0 rg'));
      } finally {
        await document.close();
      }
    });

    test('fill-opacity vira um estado gráfico estendido', () async {
      final bytes = await SvgConverter.convertToBytes(
          '<svg width="40" height="40"><rect width="10" height="10" '
          'fill="red" fill-opacity="0.5"/></svg>');

      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final content = String.fromCharCodes(
            await (await document.pageAt(1))!.contentPayload());
        // A transparência não cabe num operador de cor: precisa de um ExtGState
        // nomeado nos recursos da página.
        expect(content, contains(' gs\n'));
        expect(content, contains('1 0 0 rg\n'));
      } finally {
        await document.close();
      }
    });

    test('drawOnPage ancora no canto superior esquerdo da página', () async {
      final output = BytesBuilder(copy: false);
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
      final page = await document.appendBlankPage(PageSize.A5);
      await SvgConverter.drawOnPage(
          '<svg width="100" height="60"><rect width="10" height="10"/></svg>',
          page);
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
      try {
        final content = String.fromCharCodes(
            await (await reopened.pageAt(1))!.contentPayload());
        // A5 tem 595 pt de altura; o desenho de 45 pt encosta no topo.
        expect(content, contains('1 0 0 -1 0 595 cm'));
        expect(content, contains('0 0 75 45 re'));
      } finally {
        await reopened.close();
      }
    });

    test('ancora o desenho no topo da página quando ela já existe', () async {
      final bytes = await SvgConverter.convertToBytes(
          '<svg width="100" height="100"><rect width="10" height="10"/></svg>',
          pageSize: PageSize.A4);

      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final page = (await document.pageAt(1))!;
        final bounds = await page.mediaBounds();
        expect(bounds.getHeight(), closeTo(842, 1e-9));

        final content = String.fromCharCodes(await page.contentPayload());
        // O SVG de 75 pt de altura fica encostado na borda superior.
        expect(content, contains('1 0 0 -1 0 842 cm'));
      } finally {
        await document.close();
      }
    });
  });
}
