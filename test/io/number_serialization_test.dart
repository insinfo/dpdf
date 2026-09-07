import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

void main() {
  test('integer tokens retain all signed 64-bit digits on VM', () {
    for (final text in ['-9223372036854775808', '9223372036854775807']) {
      final value = int.parse(text);
      expect(String.fromCharCodes(ByteUtils.getIsoBytesFromInt(value)), text);
    }
  });

  test('decimal tokens trim fractions without exponent notation', () {
    final previous = ByteUtils.highPrecision;
    try {
      ByteUtils.highPrecision = false;
      for (final pair in <double, String>{
        -0.0: '0',
        0.00001: '0',
        0.00002: '0.00002',
        0.999999: '1',
        12.125: '12.13',
        -12.125: '-12.13',
        32768.5: '32769',
      }.entries) {
        expect(String.fromCharCodes(ByteUtils.getIsoBytesFromDouble(pair.key)),
            pair.value);
      }
      ByteUtils.highPrecision = true;
      expect(String.fromCharCodes(ByteUtils.getIsoBytesFromDouble(1e21)),
          '1000000000000000000000');
      expect(String.fromCharCodes(ByteUtils.getIsoBytesFromDouble(-0.000002)),
          '-0.000002');
    } finally {
      ByteUtils.highPrecision = previous;
    }
  });
}
