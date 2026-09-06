import 'dart:typed_data';
import 'package:pdfcraft/src/commons/digest/digest_bytes.dart';
import 'package:pdfcraft/src/commons/digest/keccak_digest.dart';
import 'package:pointycastle/export.dart' as reference;
import 'package:test/test.dart';

void main() {
  for (final bits in [224, 256, 384, 512]) {
    test('SHA3-$bits: reference and rate boundaries', () {
      final rate = (1600 - 2 * bits) ~/ 8;
      for (final length in [0, 1, rate - 1, rate, rate + 1, 2 * rate, 4096]) {
        final data = Uint8List.fromList(List.generate(length, (i) => i % 251));
        expect(DigestBytes.compute('SHA3-$bits', data),
            reference.SHA3Digest(bits).process(data),
            reason: 'length $length');
        expect(DigestBytes.compute('SHA-3/$bits', data),
            reference.SHA3Digest(bits).process(data));
      }
    });
  }
  for (final bits in [128, 256]) {
    test('SHAKE$bits: absorption and multi-block squeezing', () {
      final rate = (1600 - 2 * bits) ~/ 8;
      for (final length in [0, rate - 1, rate, rate + 1]) {
        final data = Uint8List.fromList(List.generate(length, (i) => i % 251));
        final oracle = reference.SHAKEDigest(bits);
        oracle.update(data, 0, data.length);
        final expected = Uint8List(400);
        oracle.doFinalRange(expected, 0, expected.length);
        expect(KeccakDigest.shake(data, bits, 400), expected);
        expect(
            DigestBytes.compute('SHAKE$bits', data), expected.take(bits ~/ 4));
      }
    });
  }
}
