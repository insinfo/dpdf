import 'package:dpdf/src/kernel/pdf/colorspace/pdf_shading.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:test/test.dart';

void main() {
  test('axialRgb cria shading e função exponencial completos', () async {
    final shading = PdfShading.axialRgb(
        1, 2, 30, 40, const [1, 0, 0], const [0, 0, 1],
        extendEnd: false);
    final dictionary = shading.pdfRepresentation();

    expect((await dictionary.numberEntry(PdfName.shadingType))!.intValue(), 2);
    expect((await dictionary.nameEntry(PdfName.colorSpace))!.getValue(),
        'DeviceRGB');
    expect(await _numbers(await dictionary.arrayEntry(PdfName.coords)),
        [1, 2, 30, 40]);
    final function =
        await dictionary.dictionaryEntry(PdfName.function) as PdfDictionary;
    expect(
        (await function.numberEntry(PdfName.intern('FunctionType')))!
            .intValue(),
        2);
    expect(await _numbers(await function.arrayEntry(PdfName.intern('C0'))),
        [1, 0, 0]);
    expect(await _numbers(await function.arrayEntry(PdfName.intern('C1'))),
        [0, 0, 1]);
    final extend =
        await dictionary.arrayEntry(PdfName.intern('Extend')) as PdfArray;
    expect((await extend.get(0) as PdfBoolean).getValue(), isTrue);
    expect((await extend.get(1) as PdfBoolean).getValue(), isFalse);
  });

  test('radialRgb valida raios e componentes', () {
    expect(
        () => PdfShading.radialRgb(
            0, 0, -1, 0, 0, 2, const [0, 0, 0], const [1, 1, 1]),
        throwsArgumentError);
    expect(
        () => PdfShading.axialRgb(0, 0, 1, 1, const [2, 0, 0], const [1, 1, 1]),
        throwsArgumentError);
  });

  test('várias paradas produzem função de stitching tipo 3', () async {
    final shading = PdfShading.axialRgbStops(
      0,
      0,
      100,
      0,
      const [0, 0.25, 1],
      const [
        [1, 0, 0],
        [0, 1, 0],
        [0, 0, 1],
      ],
    );
    final function = await shading
        .pdfRepresentation()
        .dictionaryEntry(PdfName.function) as PdfDictionary;
    expect(
        (await function.numberEntry(PdfName.intern('FunctionType')))!
            .intValue(),
        3);
    expect(await _numbers(await function.arrayEntry(PdfName.intern('Bounds'))),
        [0.25]);
    expect((await function.arrayEntry(PdfName.intern('Functions')))!.size(), 2);
    expect(await _numbers(await function.arrayEntry(PdfName.intern('Encode'))),
        [0, 1, 0, 1]);
  });
}

Future<List<double>> _numbers(PdfArray? array) async {
  final values = <double>[];
  for (var i = 0; i < array!.size(); i++) {
    values.add((await array.numberEntry(i))!.doubleValue());
  }
  return values;
}
