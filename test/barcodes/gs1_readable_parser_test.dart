import 'package:dpdf/src/barcodes/barcode_128.dart';
import 'package:test/test.dart';

void main() {
  final separator = String.fromCharCode(Barcode128.FNC1);
  test(
      'static GS1 formatter initializes identifiers without a barcode instance',
      () {
    expect(Barcode128.getHumanReadableUCCEAN('010123456789012817250101'),
        '(01)01234567890128(17)250101');
    expect(Barcode128.getHumanReadableUCCEAN('3102001234'), '(3102)001234');
  });
  test('variable fields end at FNC1 or the end of the input', () {
    expect(
        Barcode128.getHumanReadableUCCEAN(
            '${separator}10LOT42${separator}21SERIAL'),
        '(10)LOT42(21)SERIAL');
    expect(Barcode128.getHumanReadableUCCEAN('10LOT42'), '(10)LOT42');
  });
  test('malformed identifiers and truncated fields preserve readable text', () {
    expect(Barcode128.getHumanReadableUCCEAN('xx1234'), 'xx1234');
    expect(Barcode128.getHumanReadableUCCEAN('01123'), '(01)123');
    expect(Barcode128.getHumanReadableUCCEAN('01123${separator}17250101'),
        '(01)12317250101');
    expect(Barcode128.getHumanReadableUCCEAN(''), '');
    expect(Barcode128.getHumanReadableUCCEAN('$separator$separator'), '');
  });
}
