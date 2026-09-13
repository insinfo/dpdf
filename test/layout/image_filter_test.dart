import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// Um PNG entra no documento com os dados do `IDAT` intactos: já vêm
/// comprimidos com deflate e com o preditor por linha do próprio formato.
///
/// O XObject saía com `/DecodeParms << /Predictor 15 ... >>` e **sem**
/// `/Filter`. A 7.3.8.2 define os parâmetros como sendo *do filtro*, então sem
/// ele o dicionário não diz como descomprimir coisa alguma, e o fluxo fica
/// indecodificável para qualquer leitor que siga a norma — inclusive o deste
/// pacote, que desenhava a página sem a imagem e a contava como pulada.
///
/// O defeito estava do lado de quem ESCREVE: `ImageData.setDeflated(true)` era
/// chamado num lugar e lido em nenhum. Um leitor tolerante ainda assim
/// desenhava (o MuPDF adivinha o zlib), o que fazia o arquivo parecer bom.
void main() {
  group('imagem PNG no layout', () {
    late Uint8List bytes;

    setUpAll(() async {
      final saida = BytesBuilder(copy: false);
      final pdf = PdfDocument.create(PdfWriter.fromBytesBuilder(saida));
      final doc = Document(pdf, PageSize.A4);
      final imagem = Image(ImageDataFactory.create(
          File('test/assets/shapes-rgb.png').readAsBytesSync()))
        ..setWidth(120);
      await doc.add(Div()..add(imagem));
      await doc.close();
      await pdf.close();
      bytes = saida.takeBytes();
    });

    test('o XObject declara o filtro que os dados realmente usam', () async {
      final doc = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final pagina = await doc.pageAt(1);
        final recursos =
            await pagina!.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final xobjs = await recursos!.dictionaryEntry(PdfName('XObject'));
        expect(xobjs, isNotNull, reason: 'a imagem não entrou nos recursos');

        var encontradas = 0;
        for (final chave in await xobjs!.entrySet()) {
          final obj = await xobjs.get(chave.key, true);
          if (obj is! PdfStream) continue;
          final subtipo = await obj.nameEntry(PdfName.subtype);
          if (subtipo?.getValue() != 'Image') continue;
          encontradas++;
          final parms = await obj.get(PdfName.decodeParms, true);
          if (parms == null) continue;
          // Parâmetro de filtro sem filtro é dicionário que não descreve nada.
          expect(await obj.get(PdfName.filter, true), isNotNull,
              reason: 'o XObject traz /DecodeParms e nenhum /Filter');
        }
        expect(encontradas, greaterThan(0), reason: 'nenhuma imagem no PDF');
      } finally {
        await doc.close();
      }
    });

    test('a imagem chega a ser desenhada', () async {
      final doc = await PdfDocument.open(PdfReader.fromBytes(bytes));
      try {
        final r = await PdfPageRenderer.render((await doc.pageAt(1))!,
            options: const PdfRenderOptions(dpi: 72));
        expect(r.report.imagesSkipped, 0,
            reason: 'a imagem foi recusada: ${r.report}');

        var tinta = 0.0;
        for (final c in r.pixels) {
          final cinza = ((c >> 16 & 0xFF) + (c >> 8 & 0xFF) + (c & 0xFF)) / 3;
          tinta += (255 - cinza) / 255;
        }
        expect(tinta, greaterThan(100),
            reason: 'a página saiu em branco, sem a imagem');
      } finally {
        await doc.close();
      }
    });
  });
}
