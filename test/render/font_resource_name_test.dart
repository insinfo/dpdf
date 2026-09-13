import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// O nome de um recurso só tem significado dentro do `/Resources` em que
/// aparece (ISO 32000-1 7.8.3). Produtores reaproveitam nomes curtos, e um
/// mesmo documento traz `/TT0` apontando para fontes diferentes em Form
/// XObjects diferentes — foi assim num diário oficial gerado por outra
/// ferramenta, onde três fontes se chamavam `TT0`.
///
/// Guardar a fonte resolvida por NOME faz a primeira valer para todas. O
/// sintoma engana: onde o subconjunto errado não tem o glifo sai espaço em
/// branco, e onde tem sai a letra errada. Nenhum glifo é "pulado", então
/// nenhum relatório acusa nada.

PdfDictionary _fonte(String baseFont) => PdfDictionary()
  ..put(PdfName.type, PdfName('Font'))
  ..put(PdfName.subtype, PdfName('Type1'))
  ..put(PdfName.baseFont, PdfName(baseFont));

/// Form XObject que desenha [texto] com uma fonte chamada `/F1`, seja ela
/// qual for: o nome é sempre o mesmo, a fonte é que muda.
PdfStream _forma(String baseFont, String texto, double y) {
  final conteudo = 'BT /F1 24 Tf 4 $y Td ($texto) Tj ET';
  final fontes = PdfDictionary()..put(PdfName('F1'), _fonte(baseFont));
  final stream = PdfStream.withBytes(
      Uint8List.fromList(latin1.encode(conteudo)), 0)
    ..put(PdfName.type, PdfName('XObject'))
    ..put(PdfName.subtype, PdfName('Form'))
    ..put(PdfName('BBox'), PdfArray.fromDoubles([0, 0, 120, 100]))
    ..put(PdfName.resources,
        PdfDictionary()..put(PdfName('Font'), fontes));
  return stream;
}

Future<PdfRenderedPage> _render(String conteudo, PdfDictionary recursos) async {
  final saida = BytesBuilder(copy: false);
  final documento = PdfDocument.create(PdfWriter.fromBytesBuilder(saida));
  final pagina = await documento.appendBlankPage();
  pagina.pdfRepresentation()
    ..put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, 120, 100]))
    ..put(PdfName.contents,
        PdfStream.withBytes(Uint8List.fromList(latin1.encode(conteudo)), 0))
    ..put(PdfName.resources, recursos);
  await documento.close();

  final lido = await PdfDocument.open(PdfReader.fromBytes(saida.takeBytes()));
  try {
    return await PdfPageRenderer.render((await lido.pageAt(1))!,
        options: const PdfRenderOptions(dpi: 72));
  } finally {
    await lido.close();
  }
}

/// Tinta da faixa de linhas [y0], [y1): soma de `(255 - cinza) / 255`.
double _tinta(PdfRenderedPage p, int y0, int y1) {
  var soma = 0.0;
  for (var y = y0; y < y1 && y < p.height; y++) {
    for (var x = 0; x < p.width; x++) {
      final c = p.pixels[y * p.width + x];
      final cinza = ((c >> 16 & 0xFF) + (c >> 8 & 0xFF) + (c & 0xFF)) / 3;
      soma += (255 - cinza) / 255;
    }
  }
  return soma;
}

void main() {
  group('nome de recurso de fonte é local ao /Resources', () {
    // A faixa de cima recebe a forma com Helvetica; a de baixo, a com
    // ZapfDingbats. Os dois Form XObjects chamam a fonte de `/F1`.
    //
    // Os recursos sao construidos a cada chamada: escrever um PdfStream num
    // documento lhe da uma referencia indireta, e reaproveita-lo noutro faria
    // o segundo documento sair sem o objeto.
    PdfDictionary recursosColisao() => PdfDictionary()
      ..put(
          PdfName('XObject'),
          PdfDictionary()
            ..put(PdfName('Xa'), _forma('Helvetica', 'ABC', 60))
            ..put(PdfName('Xb'), _forma('ZapfDingbats', 'ABC', 20)));

    PdfDictionary recursosSozinho() => PdfDictionary()
      ..put(
          PdfName('XObject'),
          PdfDictionary()
            ..put(PdfName('Xb'), _forma('ZapfDingbats', 'ABC', 20)));

    test('dois Form XObjects com /F1 diferente desenham fontes diferentes',
        () async {
      final p = await _render('/Xa Do /Xb Do', recursosColisao());

      // Com a fonte guardada por nome, a segunda forma herdaria a Helvetica da
      // primeira e as duas faixas sairiam com o mesmo desenho.
      final cima = _tinta(p, 12, 44);
      final baixo = _tinta(p, 52, 84);
      expect(cima, greaterThan(1.0), reason: 'a faixa de cima não desenhou');
      expect(baixo, greaterThan(1.0), reason: 'a faixa de baixo não desenhou');
      expect((cima - baixo).abs() / cima, greaterThan(0.15),
          reason: 'as duas faixas têm a mesma quantidade de tinta, o que '
              'indica que ZapfDingbats foi desenhada como Helvetica');
    });

    test('a segunda forma desenha o mesmo com e sem a colisão de nome',
        () async {
      final comColisao = await _render('/Xa Do /Xb Do', recursosColisao());
      final sozinha = await _render('/Xb Do', recursosSozinho());

      // Este é o teste decisivo: a presença de outra fonte chamada `/F1` em
      // outro Form XObject não pode mudar coisa alguma no que esta desenha.
      final a = _tinta(comColisao, 52, 84);
      final b = _tinta(sozinha, 52, 84);
      expect(a, closeTo(b, 0.01),
          reason: 'a forma vizinha mudou o que esta desenhou');
    });
  });
}
