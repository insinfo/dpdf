import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// `/Interpolate` fala de AMPLIAR (8.9.5.1). Ao reduzir, amostrar por ponto
/// não é fidelidade, é alias: uma origem de 100 linhas desenhada em 72 visita
/// 72 delas e joga 28 fora. Num desenho com traços de um pixel, o traço some.
///
/// Foi assim que isto apareceu: num diário oficial, o brasão perdia o contorno
/// prateado que o MuPDF e o pdf.js desenham, e a página só voltava a bater em
/// 288 dpi, quando a imagem passa a ser ampliada em vez de reduzida.

/// Imagem em cinza com linhas alternadas pretas e brancas de um pixel.
///
/// É o pior caso para amostragem por ponto e o melhor para revelá-la: a média
/// de qualquer região é 50 % de cinza, então integrar a área dá cinza uniforme
/// e amostrar por ponto dá faixas pretas e brancas.
PdfStream _listrada(int lado) {
  final amostras = Uint8List(lado * lado);
  for (var y = 0; y < lado; y++) {
    final v = y.isEven ? 0 : 255;
    for (var x = 0; x < lado; x++) {
      amostras[y * lado + x] = v;
    }
  }
  return PdfStream.withBytes(amostras, 0)
    ..put(PdfName.type, PdfName('XObject'))
    ..put(PdfName.subtype, PdfName('Image'))
    ..put(PdfName('Width'), PdfNumber(lado.toDouble()))
    ..put(PdfName('Height'), PdfNumber(lado.toDouble()))
    ..put(PdfName('ColorSpace'), PdfName('DeviceGray'))
    ..put(PdfName('BitsPerComponent'), PdfNumber(8.0));
}

Future<PdfRenderedPage> _render(int origem, double destino) async {
  final saida = BytesBuilder(copy: false);
  final documento = PdfDocument.create(PdfWriter.fromBytesBuilder(saida));
  final pagina = await documento.appendBlankPage();
  final conteudo = 'q $destino 0 0 $destino 0 0 cm /Im Do Q';
  pagina.pdfRepresentation()
    ..put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, destino, destino]))
    ..put(PdfName.contents,
        PdfStream.withBytes(Uint8List.fromList(latin1.encode(conteudo)), 0))
    ..put(
        PdfName.resources,
        PdfDictionary()
          ..put(PdfName('XObject'),
              PdfDictionary()..put(PdfName('Im'), _listrada(origem))));
  await documento.close();

  final lido = await PdfDocument.open(PdfReader.fromBytes(saida.takeBytes()));
  try {
    return await PdfPageRenderer.render((await lido.pageAt(1))!,
        options: const PdfRenderOptions(dpi: 72));
  } finally {
    await lido.close();
  }
}

int _cinza(PdfRenderedPage p, int x, int y) {
  final c = p.pixels[y * p.width + x];
  return ((c >> 16 & 0xFF) + (c >> 8 & 0xFF) + (c & 0xFF)) ~/ 3;
}

void main() {
  group('imagem reduzida integra a área em vez de amostrar por ponto', () {
    test('uma redução de 1,39x não deixa nenhum pixel preto nem branco',
        () async {
      // 100 para 72 é 1,39x: abaixo do limiar em que o dgfx liga o filtro de
      // caixa sozinho, e exatamente o fator do diário oficial que expôs isto.
      final p = await _render(100, 72);

      var extremos = 0;
      var menor = 255;
      var maior = 0;
      for (var y = 2; y < p.height - 2; y++) {
        for (var x = 2; x < p.width - 2; x++) {
          final v = _cinza(p, x, y);
          if (v < 40 || v > 215) extremos++;
          if (v < menor) menor = v;
          if (v > maior) maior = v;
        }
      }
      expect(extremos, 0,
          reason: 'pixels saturados indicam amostragem por ponto: as linhas '
              'de um pixel viraram faixas em vez de cinza. Menor=$menor '
              'maior=$maior');
      expect((menor + maior) / 2, closeTo(128, 24),
          reason: 'a média de listras alternadas é meio cinza');
    });

    test('uma redução grande continua integrando', () async {
      final p = await _render(400, 72);
      for (var y = 2; y < p.height - 2; y++) {
        for (var x = 2; x < p.width - 2; x++) {
          expect(_cinza(p, x, y), closeTo(128, 40));
        }
      }
    });

    test('em 1:1 a imagem continua nítida, sem borrar', () async {
      // O contrário também tem de valer: sem redução, nada de filtro. Um
      // código de barras colocado em 1:1 não pode sair borrado.
      final p = await _render(72, 72);
      var pretos = 0;
      var brancos = 0;
      for (var y = 2; y < p.height - 2; y++) {
        final v = _cinza(p, p.width ~/ 2, y);
        if (v < 20) pretos++;
        if (v > 235) brancos++;
      }
      expect(pretos, greaterThan(20), reason: 'as linhas pretas sumiram');
      expect(brancos, greaterThan(20), reason: 'as linhas brancas sumiram');
    });
  });
}
