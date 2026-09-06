import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pointycastle/export.dart' as oracle;
import 'package:pdfcraft/src/pki/triple_des.dart';

void main() {
  final key = Uint8List.fromList(List.generate(24, (n) => n * 11 + 3));
  final iv = Uint8List.fromList([8, 7, 6, 5, 4, 3, 2, 1]);
  Uint8List encrypt(Uint8List padded) {
    final cipher = oracle.CBCBlockCipher(oracle.DESedeEngine())
      ..init(true, oracle.ParametersWithIV(oracle.KeyParameter(key), iv));
    final out = Uint8List(padded.length);
    for (var offset = 0; offset < padded.length; offset += 8) {
      cipher.processBlock(padded, offset, out, offset);
    }
    return out;
  }

  for (final length in [0, 1, 7, 8, 9, 16, 31, 128]) {
    test('Triple DES CBC oracle plaintext length $length', () {
      final original =
          Uint8List.fromList(List.generate(length, (n) => n * 19 + 131));
      final padding = 8 - length % 8;
      final padded =
          Uint8List.fromList([...original, ...List.filled(padding, padding)]);
      final encrypted = encrypt(padded);
      expect(TripleDes.decryptCbc(encrypted, key: key, iv: iv), original);
    });
  }
  test('rejects malformed padding and input sizes', () {
    for (final data in [
      [1, 2, 3, 4, 5, 6, 7, 0],
      [1, 2, 3, 4, 5, 6, 7, 9],
      [1, 2, 3, 4, 5, 6, 1, 2]
    ]) {
      expect(
          () => TripleDes.decryptCbc(encrypt(Uint8List.fromList(data)),
              key: key, iv: iv),
          throwsFormatException);
    }
    expect(() => TripleDes.decryptCbc(Uint8List(0), key: key, iv: iv),
        throwsArgumentError);
    expect(() => TripleDes.decryptCbc(Uint8List(7), key: key, iv: iv),
        throwsArgumentError);
    expect(() => TripleDes.decryptCbc(Uint8List(8), key: Uint8List(16), iv: iv),
        throwsArgumentError);
  });
}
