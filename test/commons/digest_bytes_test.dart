import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as reference;
import 'package:dpdf/src/commons/digest/digest_bytes.dart';
import 'package:test/test.dart';

void main() {
  final algorithms = {
    'MD5': reference.md5,
    'SHA-1': reference.sha1,
    'SHA-224': reference.sha224,
    'SHA-256': reference.sha256,
    'SHA-384': reference.sha384,
    'SHA-512': reference.sha512,
  };
  for (final entry in algorithms.entries) {
    test('${entry.key}: standard message and padding boundaries', () {
      final inputs = <Uint8List>[
        Uint8List(0),
        Uint8List.fromList(utf8.encode('abc')),
        for (final length in [
          1,
          55,
          56,
          63,
          64,
          65,
          111,
          112,
          127,
          128,
          129,
          255,
          256,
          4096,
          65536
        ])
          Uint8List.fromList(
              List.generate(length, (i) => (i * 37 + (i ~/ 251)) & 255)),
      ];
      for (final input in inputs) {
        expect(DigestBytes.compute(entry.key, input),
            entry.value.convert(input).bytes,
            reason: '${entry.key} with ${input.length} input bytes');
      }
    });
  }
  test('SHA-256 published abc digest', () {
    final actual =
        DigestBytes.compute('SHA256', Uint8List.fromList([97, 98, 99]));
    expect(actual.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
  test('rejects an unknown algorithm', () {
    expect(() => DigestBytes.compute('unknown', Uint8List(0)),
        throwsArgumentError);
  });
}
