import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:pdfcraft/src/commons/digest/legacy_digest.dart';

void main() {
  for (final name in ['MD2', 'RIPEMD-128', 'RIPEMD-160', 'RIPEMD-256']) {
    test('$name matches independent oracle across padding boundaries', () {
      for (final size in [
        0,
        1,
        15,
        16,
        17,
        55,
        56,
        63,
        64,
        65,
        127,
        128,
        129,
        1024
      ]) {
        final data =
            Uint8List.fromList(List.generate(size, (i) => (i * 37 + 13) & 255));
        expect(LegacyDigest.compute(name, data), pc.Digest(name).process(data),
            reason: '$name size=$size');
      }
    });
  }
}
