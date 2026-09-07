import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as oracle;
import 'package:dpdf/src/commons/digest/sdk_message_digest.dart';
import 'package:dpdf/src/kernel/crypto/digest_algorithms.dart';
import 'package:test/test.dart';

void main() {
  test('Adapter copies slices and resets after digest and reset', () {
    final digest = SdkMessageDigest('SHA-256');
    final data = Uint8List.fromList([0, 97, 98, 99, 255]);
    digest.update(data, 1, 3);
    data[2] = 0;
    expect(digest.digest(), oracle.sha256.convert(utf8.encode('abc')).bytes);
    expect(digest.digest(), oracle.sha256.convert([]).bytes);
    digest.updateAll(Uint8List.fromList([1]));
    expect(() => digest.update(data, 4, 2), throwsRangeError);
    expect(digest.digest(), oracle.sha256.convert([1]).bytes);
    digest.updateAll(data);
    digest.reset();
    expect(digest.digestWithInput(Uint8List.fromList([2])),
        oracle.sha256.convert([2]).bytes);
  });
  test('Kernel factory normalizes SHA3, SHAKE and legacy digest names', () {
    final expected = {
      'md-2': 128,
      'MD5': 128,
      'sha/1': 160,
      'SHA-224': 224,
      'sha256': 256,
      'SHA384': 384,
      'SHA512': 512,
      'RIPEMD-128': 128,
      'RIPEMD160': 160,
      'RIPEMD256': 256,
      'SHA3-224': 224,
      'sha-3/256': 256,
      'SHA3-384': 384,
      'SHA3-512': 512,
      'SHAKE128': 256,
      'SHAKE256': 512
    };
    for (final entry in expected.entries) {
      final digest = DigestAlgorithms.getMessageDigest(entry.key);
      expect(digest.getDigestLength() * 8, entry.value);
      expect(digest.digest().length * 8, entry.value);
      expect(DigestAlgorithms.getOutputBitLength(entry.key), entry.value);
    }
    final hash = DigestAlgorithms.getMessageDigest('SHA3-256').digest();
    expect(hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a');
    expect(DigestAlgorithms.getOutputBitLength('unknown'), 0);
    expect(() => DigestAlgorithms.getMessageDigest('GOST3411'),
        throwsArgumentError);
  });
}
