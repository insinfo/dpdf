import 'package:pdfcraft/src/barcodes/qrcode/gf_256.dart';
import 'package:pdfcraft/src/barcodes/qrcode/reed_solomon_encoder.dart';
import 'package:test/test.dart';

void main() {
  for (final item in [
    (CraftGF256.QR_CODE_FIELD, 0x11d),
    (CraftGF256.DATA_MATRIX_FIELD, 0x12d)
  ]) {
    test('all byte products match the multiplicative cycle ${item.$2}', () {
      final powers = <int>[1];
      for (var i = 1; i < 255; i++) {
        var next = powers.last << 1;
        if (next >= 256) next ^= item.$2;
        powers.add(next);
      }
      expect(powers.toSet().length, 255);
      for (var i = 0; i < 255; i++) {
        expect(item.$1.log(powers[i]), i);
        expect(item.$1.exp(i), powers[i]);
        expect(item.$1.multiply(powers[i], item.$1.inverse(powers[i])), 1);
        for (var j = 0; j < 255; j++) {
          expect(item.$1.multiply(powers[i], powers[j]), powers[(i + j) % 255]);
        }
      }
      for (var i = 0; i < 256; i++) {
        expect(item.$1.multiply(0, i), 0);
        expect(item.$1.multiply(i, 0), 0);
      }
    });
  }
  test('QR codeword has zero syndrome at each generator root', () {
    final field = CraftGF256.QR_CODE_FIELD;
    final encoder = CraftReedSolomonEncoder(field);
    for (final paritySize in [7, 10, 18, 30]) {
      final payload = List<int>.generate(97, (i) => (i * 73 + 11) % 256);
      final word = [...payload, ...List<int>.filled(paritySize, 199)];
      encoder.encode(word, paritySize);
      expect(word.take(payload.length), payload);
      for (var rootIndex = 0; rootIndex < paritySize; rootIndex++) {
        final root = field.exp(rootIndex);
        var syndrome = 0;
        for (final coefficient in word) {
          syndrome = field.multiply(syndrome, root) ^ coefficient;
        }
        expect(syndrome, 0, reason: 'parity $paritySize, root $rootIndex');
      }
    }
  });
  test('invalid fields and bytes fail before changing the buffer', () {
    expect(() => CraftGF256.QR_CODE_FIELD.inverse(0), throwsArgumentError);
    expect(
        () => CraftGF256.QR_CODE_FIELD.multiply(256, 1), throwsArgumentError);
    expect(() => CraftReedSolomonEncoder(CraftGF256.DATA_MATRIX_FIELD),
        throwsArgumentError);
    final input = [300, 0, 0];
    expect(
        () =>
            CraftReedSolomonEncoder(CraftGF256.QR_CODE_FIELD).encode(input, 2),
        throwsArgumentError);
    expect(input, [300, 0, 0]);
  });
}
