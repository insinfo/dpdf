import 'package:dpdf/src/barcodes/barcode_ean.dart';
import 'package:test/test.dart';

void main() {
  test('retail and supplement module widths follow their symbol families', () {
    final cases = [
      (CraftBarcodeEAN.getBarsEAN13('4006381333931'), 59, 95),
      (CraftBarcodeEAN.getBarsEAN8('96385074'), 43, 67),
      (CraftBarcodeEAN.getBarsUPCE('04252614'), 33, 51),
      (CraftBarcodeEAN.getBarsSupplemental2('05'), 13, 20),
      (CraftBarcodeEAN.getBarsSupplemental5('51234'), 31, 47),
    ];
    for (final (bars, count, width) in cases) {
      expect(bars.length, count);
      expect(bars.fold<int>(0, (sum, value) => sum + value), width);
      expect(bars.every((value) => value >= 1 && value <= 4), isTrue);
    }
  });
  test('check digits and UPC zero suppression cover each compression case', () {
    expect(CraftBarcodeEAN.calculateEANParity('400638133393'), 1);
    expect(CraftBarcodeEAN.calculateEANParity('9638507'), 4);
    expect(CraftBarcodeEAN.convertUPCAtoUPCE('042100005264'), '04252614');
    expect(CraftBarcodeEAN.convertUPCAtoUPCE('012300000451'), '01234531');
    expect(CraftBarcodeEAN.convertUPCAtoUPCE('012340000051'), '01234541');
    expect(CraftBarcodeEAN.convertUPCAtoUPCE('012345000061'), '01234561');
    expect(CraftBarcodeEAN.convertUPCAtoUPCE('012345678901'), isNull);
    expect(CraftBarcodeEAN.convertUPCAtoUPCE('0123450000x1'), isNull);
  });
  test('supplement parity reverses the expected digit run sequence', () {
    expect(CraftBarcodeEAN.getBarsSupplemental2('05'),
        [1, 1, 2, 3, 2, 1, 1, 1, 1, 1, 3, 2, 1]);
    final zero = CraftBarcodeEAN.getBarsUPCE('04252614');
    final one = CraftBarcodeEAN.getBarsUPCE('14252614');
    for (var offset = 3; offset < 27; offset += 4) {
      expect(one.sublist(offset, offset + 4),
          zero.sublist(offset, offset + 4).reversed.toList());
    }
  });
  test(
      'invalid retail input never silently truncates or indexes outside tables',
      () {
    expect(() => CraftBarcodeEAN.getBarsEAN13('40063813339310'),
        throwsFormatException);
    expect(
        () => CraftBarcodeEAN.getBarsEAN8('9638507x'), throwsFormatException);
    expect(
        () => CraftBarcodeEAN.getBarsUPCE('24252614'), throwsFormatException);
    expect(() => CraftBarcodeEAN.getBarsSupplemental2('051'),
        throwsFormatException);
    expect(() => CraftBarcodeEAN.getBarsSupplemental5('51'),
        throwsFormatException);
  });
}
