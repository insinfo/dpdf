import 'package:dpdf/src/barcodes/qrcode/bit_vector.dart';
import 'package:dpdf/src/barcodes/qrcode/encoder.dart';
import 'package:dpdf/src/barcodes/qrcode/encode_hint_type.dart';
import 'package:dpdf/src/barcodes/qrcode/error_correction_level.dart';
import 'package:dpdf/src/barcodes/qrcode/mode.dart';
import 'package:dpdf/src/barcodes/qrcode/qr_code.dart';
import 'package:test/test.dart';

void main() {
  CraftQRCode symbol(String text, [String encoding = 'ISO-8859-1']) {
    final result = CraftQRCode();
    CraftEncoder.encode(text, CraftErrorCorrectionLevel.L,
        {CraftEncodeHintType.CHARACTER_SET: encoding}, result);
    return result;
  }

  test('version one admits its exact numeric and byte capacity', () {
    expect(symbol('1' * 41).formatVersion(), 1);
    expect(symbol('1' * 42).formatVersion(), 2);
    expect(symbol('a' * 17).formatVersion(), 1);
    expect(symbol('a' * 18).formatVersion(), 2);
  });
  test('UTF-8 ECI header participates in capacity selection', () {
    expect(symbol('a' * 17).formatVersion(), 1);
    expect(symbol('a' * 17, 'UTF-8').formatVersion(), 2);
    expect(symbol('é' * 9, 'UTF-8').formatVersion(), 2);
  });
  test('numeric groups and alphanumeric pairs produce prescribed bit values',
      () {
    final numeric = CraftBitVector();
    CraftEncoder.appendBytes('1234', CraftMode.NUMERIC, numeric, 'ISO-8859-1');
    expect(numeric.size(), 14);
    expect([for (var i = 0; i < numeric.size(); i++) numeric.at(i)].join(),
        '00011110110100');
    final alpha = CraftBitVector();
    CraftEncoder.appendBytes('AB', CraftMode.ALPHANUMERIC, alpha, 'ISO-8859-1');
    expect([for (var i = 0; i < alpha.size(); i++) alpha.at(i)].join(),
        (10 * 45 + 11).toRadixString(2).padLeft(11, '0'));
  });
  test('invalid alphabet input is rejected before appending any bits', () {
    final bits = CraftBitVector()..appendBits(3, 2);
    expect(
        () => CraftEncoder.appendBytes(
            '12x', CraftMode.NUMERIC, bits, 'ISO-8859-1'),
        throwsFormatException);
    expect(bits.size(), 2);
    expect(CraftEncoder.getAlphanumericCode(-1), -1);
  });
}
