import 'package:dpdf/src/barcodes/barcode_ean.dart';
import 'package:test/test.dart';

void main() {
  test('retail and supplement module widths follow their symbol families', () {
    final cases = [
      (BarcodeEAN.getBarsEAN13('4006381333931'), 59, 95),
      (BarcodeEAN.getBarsEAN8('96385074'), 43, 67),
      (BarcodeEAN.getBarsUPCE('04252614'), 33, 51),
      (BarcodeEAN.getBarsSupplemental2('05'), 13, 20),
      (BarcodeEAN.getBarsSupplemental5('51234'), 31, 47),
    ];
    for (final (bars, count, width) in cases) {
      expect(bars.length, count);
      expect(bars.fold<int>(0, (sum, value) => sum + value), width);
      expect(bars.every((value) => value >= 1 && value <= 4), isTrue);
    }
  });
  test('check digits and UPC zero suppression cover each compression case', () {
    expect(BarcodeEAN.calculateEANParity('400638133393'), 1);
    expect(BarcodeEAN.calculateEANParity('9638507'), 4);
    expect(BarcodeEAN.convertUPCAtoUPCE('042100005264'), '04252614');
    expect(BarcodeEAN.convertUPCAtoUPCE('012300000451'), '01234531');
    expect(BarcodeEAN.convertUPCAtoUPCE('012340000051'), '01234541');
    expect(BarcodeEAN.convertUPCAtoUPCE('012345000061'), '01234561');
    expect(BarcodeEAN.convertUPCAtoUPCE('012345678901'), isNull);
    expect(BarcodeEAN.convertUPCAtoUPCE('0123450000x1'), isNull);
  });
  test('supplement parity reverses the expected digit run sequence', () {
    expect(BarcodeEAN.getBarsSupplemental2('05'),
        [1, 1, 2, 3, 2, 1, 1, 1, 1, 1, 3, 2, 1]);
    final zero = BarcodeEAN.getBarsUPCE('04252614');
    final one = BarcodeEAN.getBarsUPCE('14252614');
    for (var offset = 3; offset < 27; offset += 4) {
      expect(one.sublist(offset, offset + 4),
          zero.sublist(offset, offset + 4).reversed.toList());
    }
  });
  test(
      'invalid retail input never silently truncates or indexes outside tables',
      () {
    expect(
        () => BarcodeEAN.getBarsEAN13('40063813339310'), throwsFormatException);
    expect(() => BarcodeEAN.getBarsEAN8('9638507x'), throwsFormatException);
    expect(() => BarcodeEAN.getBarsUPCE('24252614'), throwsFormatException);
    expect(() => BarcodeEAN.getBarsSupplemental2('051'), throwsFormatException);
    expect(() => BarcodeEAN.getBarsSupplemental5('51'), throwsFormatException);
  });
}
