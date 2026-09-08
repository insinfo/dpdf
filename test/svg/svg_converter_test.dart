import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:dgfx/dgfx.dart';

import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/render/page_renderer.dart';
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

    test('style aceita seletores descendentes e de filho direto', () async {
      final content = await _render('''
        <svg width="30" height="20">
          <style>
            rect { fill: black; }
            .layer .desc { fill: red; }
            .layer > rect { stroke: blue; }
          </style>
          <g class="layer">
            <rect class="desc" width="5" height="5"/>
            <g><rect class="desc" x="10" width="5" height="5"/></g>
          </g>
        </svg>
      ''');

      expect(_count(content, '1 0 0 rg\n'), 2);
      expect(_count(content, '0 0 1 RG\n'), 1,
          reason: 'o retângulo dentro do segundo g não é filho direto');
      expect(content, isNot(contains('0 0 0 rg\n')),
          reason: 'o seletor descendente mais específico vence rect');
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

    test('clip-path reúne as formas e recorta o elemento referenciador',
        () async {
      final content = await _render('''
        <svg width="40" height="20">
          <defs>
            <clipPath id="cut">
              <rect width="4" height="6"/>
              <circle cx="10" cy="4" r="2"/>
            </clipPath>
          </defs>
          <rect width="30" height="15" fill="red" clip-path="url(#cut)"/>
        </svg>
      ''');

      final clip = content.indexOf('W\n');
      final painted = content.indexOf('0 0 22.5 11.25 re\n');
      expect(clip, greaterThan(0));
      expect(painted, greaterThan(clip));
      expect(_count(content, 'W\n'), 2,
          reason: 'há o recorte do viewport e um único recorte composto');
    });

    test('clip-rule evenodd emite W estrela', () async {
      final content = await _render('''
        <svg width="20" height="20">
          <clipPath id="cut" clip-rule="evenodd">
            <path d="M0 0h10v10h-10z M2 2h6v6h-6z"/>
          </clipPath>
          <rect width="20" height="20" clip-path="url(#cut)"/>
        </svg>
      ''');

      expect(content, contains('W*\n'));
    });

    test('marker-end desenha e orienta a seta no fim da linha', () async {
      final content = await _render('''
        <svg width="50" height="30">
          <defs>
            <marker id="arrow" markerWidth="4" markerHeight="4"
                    refX="4" refY="2" orient="auto" viewBox="0 0 4 4">
              <path d="M0 0 L4 2 L0 4 Z" fill="black"/>
            </marker>
          </defs>
          <line x1="10" y1="10" x2="30" y2="10"
                stroke="black" marker-end="url(#arrow)"/>
        </svg>
      ''');
      expect(content, contains('1 0 0 1 22.5 7.5 cm\n'));
      expect(_count(content, ' m\n'), equals(2),
          reason: 'uma linha e o path da seta devem ser emitidos');
    });

    test('marker alinha viewBox no viewport e recorta overflow por padrão',
        () async {
      Future<String> marker(String overflow) => _render('''
        <svg width="50" height="30">
          <defs>
            <marker id="m" markerUnits="userSpaceOnUse"
                    markerWidth="8" markerHeight="4" refX="5" refY="5"
                    viewBox="0 0 10 10" preserveAspectRatio="xMidYMid meet"
                    overflow="$overflow">
              <rect width="10" height="10"/>
            </marker>
          </defs>
          <line x1="2" y1="2" x2="20" y2="2" marker-end="url(#m)"/>
        </svg>
      ''');

      final hidden = await marker('hidden');
      final visible = await marker('visible');
      expect(hidden, contains('1 0 0 1 -3 -1.5 cm\n'));
      expect(hidden, contains('1 0 0 1 1.5 0 cm\n'));
      expect(_count(hidden, 'W\n'), equals(_count(visible, 'W\n') + 1));
    });

    test('marker shorthand desenha início, meios e fim da polyline', () async {
      final content = await _render('''
        <svg width="50" height="30">
          <defs>
            <marker id="dot" markerUnits="userSpaceOnUse">
              <circle cx="0" cy="0" r="1" fill="red"/>
            </marker>
          </defs>
          <polyline points="5 5 15 5 15 15 25 15"
                    fill="none" stroke="black" marker="url(#dot)"/>
        </svg>
      ''');
      expect(_count(content, ' cm\n'), greaterThanOrEqualTo(4),
          reason: 'cada um dos quatro vértices recebe um marcador');
    });

    test('path aplica markers em cada subcaminho e nas curvas', () async {
      final content = await _render('''
        <svg width="50" height="30">
          <defs>
            <marker id="dot" markerUnits="userSpaceOnUse"
                    orient="auto-start-reverse">
              <circle r="1" fill="blue"/>
            </marker>
          </defs>
          <path d="M5 5 C8 2 12 2 15 5 M20 10 L20 20"
                fill="none" stroke="black" marker="url(#dot)"/>
        </svg>
      ''');
      expect(_count(content, ' c\n'), equals(17),
          reason: 'a curva original e quatro markers circulares');
      expect(content, contains('1 0 0 1 3.75 3.75 cm\n'));
      expect(content, contains('1 0 0 1 15 15 cm\n'));
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
    const pixelPng =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

    test('text usa fonte padrão e posiciona a linha de base', () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="100" height="30">
          <text x="10" y="20" font-size="16">Hello SVG</text>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final content = String.fromCharCodes(
            await (await document.pageAt(1))!.contentPayload());
        expect(content, contains('BT\n'));
        expect(content, contains('1 0 0 -1 7.5 15 Tm\n'));
        expect(content, contains('(Hello SVG) Tj\n'));
      } finally {
        await document.close();
      }
    });

    test('text resolve uma fonte registrada no catálogo compartilhado',
        () async {
      final fontBytes =
          await File('test/assets/ABeeZee-Regular.ttf').readAsBytes();
      final fonts = BLFontCollection()
        ..addBytes(fontBytes, familyName: 'Example Sans');
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="100" height="30">
          <text font-family="Example Sans" x="2" y="20">catalog</text>
        </svg>
      ''', fontCollection: fonts);
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final page = (await document.pageAt(1))!;
        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final fontDictionary = await resources?.dictionaryEntry(PdfName.font);
        expect(fontDictionary, isNotNull);
        final content = String.fromCharCodes(await page.contentPayload());
        expect(content, contains('<004C0043007E00430067006E0056> Tj\n'));
      } finally {
        await document.close();
      }
    });

    test('tspan preserva ordem, posição própria e deslocamento relativo',
        () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="120" height="30">
          <text x="2" y="20">A<tspan x="20" dy="2">B</tspan>C</text>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final content = String.fromCharCodes(
            await (await document.pageAt(1))!.contentPayload());
        final a = content.indexOf('(A) Tj');
        final b = content.indexOf('(B) Tj');
        final c = content.indexOf('(C) Tj');
        expect(a, greaterThanOrEqualTo(0));
        expect(b, greaterThan(a));
        expect(c, greaterThan(b));
        expect(content, contains('1 0 0 -1 15 16.5 Tm\n'),
            reason: 'x=20 e y=20+dy=2 são convertidos de px para pt');
      } finally {
        await document.close();
      }
    });

    test('image incorpora data URI com a geometria declarada', () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="30" height="20">
          <image href="data:image/png;base64,$pixelPng"
                 x="2" y="3" width="10" height="8"/>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final content = String.fromCharCodes(
            await (await document.pageAt(1))!.contentPayload());
        expect(content, contains('7.5 0 0 6 1.5 2.25 cm\n'));
        expect(content, contains(' Do\n'));
      } finally {
        await document.close();
      }
    });

    test('linearGradient com três stops vira shading recortado', () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="100" height="30">
          <defs>
            <linearGradient id="paint" x1="0%" x2="100%">
              <stop offset="0%" stop-color="red"/>
              <stop offset="40%" stop-color="#00ff00"/>
              <stop offset="100%" stop-color="blue"/>
            </linearGradient>
          </defs>
          <rect x="10" y="5" width="80" height="20" fill="url(#paint)"/>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final content = String.fromCharCodes(
            await (await document.pageAt(1))!.contentPayload());
        expect(content, contains('7.5 3.75 60 15 re\n'));
        expect(content, contains('W\n'));
        expect(content, contains(' sh\n'));
        expect(content, isNot(contains('0 0 0 rg\n')),
            reason: 'o gradiente não deve virar o fallback preto');
      } finally {
        await document.close();
      }
    });

    test('radialGradient gera shading radial', () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="40" height="40">
          <radialGradient id="g">
            <stop offset="0" stop-color="white"/>
            <stop offset="1" stop-color="black"/>
          </radialGradient>
          <circle cx="20" cy="20" r="15" fill="url(#g)"/>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final page = (await document.pageAt(1))!;
        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final shadings = await resources?.dictionaryEntry(PdfName.shading);
        expect(shadings, isNotNull);
        final values = await shadings!.values();
        final first = values.first;
        expect(first, isA<PdfDictionary>());
        expect(
            (await (first as PdfDictionary).numberEntry(PdfName.shadingType))!
                .intValue(),
            3);
      } finally {
        await document.close();
      }
    });

    test('radialGradient herda foco do centro e respeita fr do SVG 2',
        () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="40" height="40">
          <radialGradient id="g" cx="25%" cy="75%" r="50%" fr="10%">
            <stop offset="0" stop-color="white"/>
            <stop offset="1" stop-color="black"/>
          </radialGradient>
          <rect x="5" y="5" width="30" height="30" fill="url(#g)"/>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final page = (await document.pageAt(1))!;
        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final shadings = await resources!.dictionaryEntry(PdfName.shading);
        final shading = (await shadings!.values()).single as PdfDictionary;
        final coords =
            await (await shading.arrayEntry(PdfName.coords))!.toDoubleArray();
        expect(coords, hasLength(6));
        expect(coords[0], closeTo(9.375, 1e-9));
        expect(coords[1], closeTo(20.625, 1e-9));
        expect(coords[2], closeTo(2.25, 1e-9));
        expect(coords[3], closeTo(coords[0], 1e-9));
        expect(coords[4], closeTo(coords[1], 1e-9));
        expect(coords[5], closeTo(11.25, 1e-9));
      } finally {
        await document.close();
      }
    });

    test('gradientTransform transforma somente o shading', () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="40" height="20">
          <linearGradient id="g" gradientTransform="translate(4 2)">
            <stop offset="0" stop-color="red"/>
            <stop offset="1" stop-color="blue"/>
          </linearGradient>
          <rect width="40" height="20" fill="url(#g)"/>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final content = String.fromCharCodes(
            await (await document.pageAt(1))!.contentPayload());
        expect(content, contains('1 0 0 1 3 1.5 cm\n'));
        expect(content.indexOf('1 0 0 1 3 1.5 cm\n'),
            lessThan(content.indexOf(' sh\n')));
      } finally {
        await document.close();
      }
    });

    test('gradiente herda stops e atributos por href sem recursão', () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="60" height="20">
          <defs>
            <linearGradient id="base" x1="10%" x2="90%">
              <stop offset="0" stop-color="red"/>
              <stop offset="1" stop-color="blue"/>
            </linearGradient>
            <linearGradient id="derived" href="#base" x2="100%"/>
          </defs>
          <rect width="60" height="20" fill="url(#derived)"/>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final page = (await document.pageAt(1))!;
        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final shadings = await resources!.dictionaryEntry(PdfName.shading);
        final shading = (await shadings!.values()).single as PdfDictionary;
        final coords = await shading.arrayEntry(PdfName.coords);
        final values = await coords!.toDoubleArray();
        expect(values[0], closeTo(4.5, 1e-9));
        expect(values[2], closeTo(45, 1e-9));
      } finally {
        await document.close();
      }
    });

    test('stop-opacity cria soft mask gradual alinhada ao shading', () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="60" height="20">
          <linearGradient id="fade" gradientTransform="translate(2 0)">
            <stop offset="0" stop-color="red" stop-opacity="0"/>
            <stop offset="50%" stop-color="green" stop-opacity="25%"/>
            <stop offset="1" stop-color="blue" stop-opacity="1"/>
          </linearGradient>
          <rect width="60" height="20" fill="url(#fade)"/>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final page = (await document.pageAt(1))!;
        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final states = await resources!.dictionaryEntry(PdfName.extGState);
        final state = (await states!.values()).single as PdfDictionary;
        final softMask = await state.dictionaryEntry(PdfName.smaskG);
        expect(
            (await softMask!.nameEntry(PdfName.s))!.getValue(), 'Luminosity');
        final group = await softMask.streamEntry(PdfName('G'));
        final maskContent = String.fromCharCodes((await group!.getBytes())!);
        expect(maskContent, contains('1 0 0 1 1.5 0 cm\n'));
        expect(maskContent, contains(' sh\n'));
        final groupResources = await group.dictionaryEntry(PdfName.resources);
        final opacityShadings =
            await groupResources!.dictionaryEntry(PdfName.shading);
        expect(await opacityShadings!.values(), hasLength(1));

        final content = String.fromCharCodes(await page.contentPayload());
        expect(
            content.indexOf(' gs\n'), lessThan(content.lastIndexOf(' sh\n')));
      } finally {
        await document.close();
      }
    });

    test('pattern vira um tiling pattern nativo com conteúdo próprio',
        () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="80" height="30">
          <defs>
            <pattern id="tiles" width="10" height="8"
                     patternUnits="userSpaceOnUse">
              <rect width="5" height="8" fill="red"/>
            </pattern>
          </defs>
          <rect x="4" y="3" width="60" height="20"
                fill="url(#tiles)" stroke="blue"/>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final page = (await document.pageAt(1))!;
        final content = String.fromCharCodes(await page.contentPayload());
        expect(content, contains('/Pattern cs\n'));
        expect(content, contains(' scn\n'));
        expect(content, contains('B\n'),
            reason: 'o caminho conserva pattern fill e stroke');
        expect(content, isNot(contains('0 0 0 rg\n')),
            reason: 'o paint server não deve cair no preenchimento preto');

        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final patterns = await resources?.dictionaryEntry(PdfName.pattern);
        expect(patterns, isNotNull);
        final values = await patterns!.values();
        expect(values, hasLength(1));
        final pattern = values.single as PdfStream;
        expect(
            (await pattern.numberEntry(PdfName('PatternType')))!.intValue(), 1);
        expect(
            (await pattern.numberEntry(PdfName('PaintType')))!.intValue(), 1);
        expect((await pattern.numberEntry(PdfName('XStep')))!.doubleValue(),
            closeTo(7.5, 1e-9));
        expect((await pattern.numberEntry(PdfName('YStep')))!.doubleValue(),
            closeTo(6, 1e-9));
        final tileContent = String.fromCharCodes((await pattern.getBytes())!);
        expect(tileContent, contains('0 0 3.75 6 re\n'));
        expect(tileContent, contains('1 0 0 rg\n'));

        final rendered = await PdfPageRenderer.render(page,
            options: const PdfRenderOptions(dpi: 72));
        int redAt(int x, int y) =>
            (rendered.pixels[y * rendered.width + x] >> 16) & 0xff;
        int greenAt(int x, int y) =>
            (rendered.pixels[y * rendered.width + x] >> 8) & 0xff;
        expect(redAt(6, 10), greaterThan(240),
            reason: 'a metade transparente deixa o fundo branco');
        expect(greenAt(11, 10), lessThan(15));
        expect(redAt(11, 10), greaterThan(240));
        expect(redAt(18, 10), greaterThan(240),
            reason: 'a célula de 7,5 pt deve recomeçar');
        expect(rendered.report.unsupportedOperators, isEmpty);
      } finally {
        await document.close();
      }
    });

    test('pattern objectBoundingBox dimensiona a célula pela geometria',
        () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="80" height="40">
          <pattern id="p" width="25%" height="50%">
            <circle cx="0.5" cy="0.5" r="0.4" fill="green"/>
          </pattern>
          <rect x="10" y="5" width="40" height="20" fill="url(#p)"/>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final page = (await document.pageAt(1))!;
        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final patterns = await resources!.dictionaryEntry(PdfName.pattern);
        final pattern = (await patterns!.values()).single as PdfStream;
        expect((await pattern.numberEntry(PdfName('XStep')))!.doubleValue(),
            closeTo(7.5, 1e-9));
        expect((await pattern.numberEntry(PdfName('YStep')))!.doubleValue(),
            closeTo(7.5, 1e-9));
      } finally {
        await document.close();
      }
    });

    test('pattern herda dimensões e filhos por xlink:href', () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg xmlns:xlink="http://www.w3.org/1999/xlink" width="40" height="20">
          <defs>
            <pattern id="base" width="8" height="6"
                     patternUnits="userSpaceOnUse">
              <rect width="4" height="6" fill="green"/>
            </pattern>
            <pattern id="derived" xlink:href="#base"/>
          </defs>
          <rect width="40" height="20" fill="url(#derived)"/>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final page = (await document.pageAt(1))!;
        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final patterns = await resources!.dictionaryEntry(PdfName.pattern);
        final pattern = (await patterns!.values()).single as PdfStream;
        expect((await pattern.numberEntry(PdfName('XStep')))!.doubleValue(), 6);
        expect(
            (await pattern.numberEntry(PdfName('YStep')))!.doubleValue(), 4.5);
        expect(String.fromCharCodes((await pattern.getBytes())!),
            contains('0 0 3 4.5 re\n'));
      } finally {
        await document.close();
      }
    });

    test('mask luminance vira soft mask com grupo de transparência', () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="80" height="40">
          <defs>
            <mask id="fade" maskUnits="userSpaceOnUse"
                  x="5" y="4" width="50" height="24">
              <rect x="5" y="4" width="25" height="24" fill="white"/>
              <rect x="30" y="4" width="25" height="24" fill="black"/>
            </mask>
          </defs>
          <rect x="5" y="4" width="50" height="24"
                fill="red" mask="url(#fade)"/>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final page = (await document.pageAt(1))!;
        final content = String.fromCharCodes(await page.contentPayload());
        expect(
            content.indexOf(' gs\n'), lessThan(content.indexOf('37.5 18 re')));

        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final states = await resources!.dictionaryEntry(PdfName.extGState);
        expect(states, isNotNull);
        final state = (await states!.values()).single as PdfDictionary;
        final softMask = await state.dictionaryEntry(PdfName.smaskG);
        expect(
            (await softMask!.nameEntry(PdfName.s))!.getValue(), 'Luminosity');
        final group = await softMask.streamEntry(PdfName('G'));
        expect(group, isNotNull);
        final groupInfo = await group!.dictionaryEntry(PdfName('Group'));
        expect((await groupInfo!.nameEntry(PdfName.s))!.getValue(),
            'Transparency');
        final maskContent = String.fromCharCodes((await group.getBytes())!);
        expect(maskContent, contains('1 1 1 rg\n'));
        expect(maskContent, contains('0 0 0 rg\n'));

        final rendered = await PdfPageRenderer.render(page,
            options: const PdfRenderOptions(dpi: 72));
        int channelAt(int x, int y, int shift) =>
            (rendered.pixels[y * rendered.width + x] >> shift) & 0xff;
        expect(channelAt(10, 15, 16), greaterThan(240));
        expect(channelAt(10, 15, 8), lessThan(15));
        expect(channelAt(35, 15, 8), greaterThan(240),
            reason: 'o trecho preto da máscara deixa aparecer o fundo branco');
        expect(rendered.report.unsupportedOperators, isEmpty);
      } finally {
        await document.close();
      }
    });

    test('mask-type alpha e maskContentUnits objectBoundingBox são emitidos',
        () async {
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="60" height="30">
          <mask id="alpha" mask-type="alpha"
                maskContentUnits="objectBoundingBox">
            <rect width="0.5" height="1" fill="white"/>
          </mask>
          <rect x="10" y="5" width="40" height="20"
                fill="blue" mask="url(#alpha)"/>
        </svg>
      ''');
      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final page = (await document.pageAt(1))!;
        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final states = await resources!.dictionaryEntry(PdfName.extGState);
        final state = (await states!.values()).single as PdfDictionary;
        final softMask = await state.dictionaryEntry(PdfName.smaskG);
        expect((await softMask!.nameEntry(PdfName.s))!.getValue(), 'Alpha');
        final group = await softMask.streamEntry(PdfName('G'));
        final maskContent = String.fromCharCodes((await group!.getBytes())!);
        expect(maskContent, contains('30 0 0 15 7.5 3.75 cm\n'));
      } finally {
        await document.close();
      }
    });

    test('image externa usa o resolvedor explícito', () async {
      Uri? requested;
      final bytes = await SvgConverter.convertToBytes('''
        <svg width="20" height="20">
          <image href="https://example.test/pixel.png"
                 width="4" height="4"/>
        </svg>
      ''', resourceLoader: (uri) async {
        requested = uri;
        return base64Decode(pixelPng);
      });
      expect(requested, Uri.parse('https://example.test/pixel.png'));

      final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final content = String.fromCharCodes(
            await (await document.pageAt(1))!.contentPayload());
        expect(content, contains('3 0 0 3 0 0 cm\n'));
        expect(content, contains(' Do\n'));
      } finally {
        await document.close();
      }
    });

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
