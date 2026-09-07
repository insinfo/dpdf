import 'dart:typed_data';
import 'package:dpdf/src/pki/pkcs12_derivation.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/key_derivators/pkcs12_parameter_generator.dart';
import 'package:test/test.dart';

void main() {
  for (final password in ['', 'Beavis', 'senhaÁ漢', 'long' * 40]) {
    test('SHA1 oracle: password length ${password.length}', () {
      final passwordBytes = Uint8List.fromList([
        for (final unit in password.codeUnits) ...[unit >> 8, unit & 255],
        0,
        0
      ]);
      for (final salt in [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3, 4, 5]),
        Uint8List.fromList(List.generate(79, (i) => i))
      ]) {
        for (final iterations in [1, 7]) {
          for (final purpose in [1, 2, 3]) {
            final oracle = PKCS12ParametersGenerator(SHA1Digest())
              ..init(passwordBytes, salt, iterations);
            final expected = switch (purpose) {
              1 => oracle.generateDerivedParameters(53).key,
              2 => oracle.generateDerivedParametersWithIV(1, 53).iv,
              _ => oracle.generateDerivedMacParameters(53).key,
            };
            expect(
                Pkcs12Derivation.deriveSha1(
                    password: password,
                    salt: salt,
                    iterations: iterations,
                    purpose: purpose,
                    length: 53),
                expected);
          }
        }
      }
    });
  }
  test('legacy empty password matches zero-byte oracle', () {
    final salt = Uint8List.fromList([1, 2, 3, 4]);
    final expected = (PKCS12ParametersGenerator(SHA1Digest())
          ..init(Uint8List(0), salt, 7))
        .generateDerivedMacParameters(20)
        .key;
    final legacy = Pkcs12Derivation.deriveSha1(
        password: '',
        salt: salt,
        iterations: 7,
        purpose: 3,
        length: 20,
        emptyPasswordIsZeroLength: true);
    expect(legacy, expected);
    expect(
        legacy,
        isNot(Pkcs12Derivation.deriveSha1(
            password: '', salt: salt, iterations: 7, purpose: 3, length: 20)));
  });
  test('zero length and parameter guards', () {
    Uint8List derive(int iterations, int purpose, int length) =>
        Pkcs12Derivation.deriveSha1(
            password: '',
            salt: Uint8List(0),
            iterations: iterations,
            purpose: purpose,
            length: length);
    expect(derive(1, 3, 0), isEmpty);
    expect(() => derive(0, 3, 1), throwsArgumentError);
    expect(() => derive(1, 0, 1), throwsArgumentError);
    expect(() => derive(1, 4, 1), throwsArgumentError);
    expect(() => derive(1, 1, -1), throwsArgumentError);
  });
}
