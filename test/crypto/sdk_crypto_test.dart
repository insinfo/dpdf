import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pointycastle/export.dart' as oracle;
import 'package:dpdf/src/pki/pki_utils.dart';
import 'package:dpdf/src/kernel/crypto/aes_cipher.dart';
import 'package:dpdf/src/sign/der_objects.dart';
import 'package:dpdf/src/sign/x509_certificate.dart';

Uint8List hex(String s) => Uint8List.fromList(List.generate(
    s.length ~/ 2, (i) => int.parse(s.substring(i * 2, i * 2 + 2), radix: 16)));
void main() {
  final iv = hex('000102030405060708090a0b0c0d0e0f');
  final plaintext =
      hex('6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51');
  final vectors = {
    '2b7e151628aed2a6abf7158809cf4f3c':
        '7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2',
    '8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b':
        '4f021db243bc633d7178183a9fa071e8b4d9ada9ad7dedf4e5e738763f69145a',
    '603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4':
        'f58c4c04d6e5f1ba779eabfb5f7bfbd69cfc4e967edb808d679f777bc6702c7d',
  };
  for (final vector in vectors.entries) {
    test('NIST SP800-38A CBC ${vector.key.length * 4}', () {
      final cipher =
          CraftAESCipher(true, hex(vector.key), iv, usePadding: false);
      final encrypted = cipher.update(plaintext, 0, plaintext.length);
      expect(cipher.doFinal(), isEmpty);
      expect(encrypted, hex(vector.value));
      final decrypt =
          CraftAESCipher(false, hex(vector.key), iv, usePadding: false);
      expect(decrypt.update(encrypted, 0, encrypted.length), plaintext);
      expect(decrypt.doFinal(), isEmpty);
    });
  }
  test('CBC padding interop for every block boundary and bytewise update', () {
    for (final keyHex in vectors.keys) {
      final key = hex(keyHex);
      for (var size = 0; size < 65; size++) {
        final message = Uint8List.fromList(List.generate(size, (i) => i));
        final pc = oracle.PaddedBlockCipherImpl(
            oracle.PKCS7Padding(), oracle.CBCBlockCipher(oracle.AESEngine()));
        pc.init(
            true,
            oracle.PaddedBlockCipherParameters(
                oracle.ParametersWithIV(oracle.KeyParameter(key), iv), null));
        final expected = size == 0
            ? (oracle.CBCBlockCipher(oracle.AESEngine())
                  ..init(true,
                      oracle.ParametersWithIV(oracle.KeyParameter(key), iv)))
                .process(Uint8List(16)..fillRange(0, 16, 16))
            : pc.process(message);
        final encrypted = PkiUtils.processAesCbc(true, key, iv, message);
        expect(encrypted, expected);
        final cipher = CraftAESCipher(false, key, iv);
        final out = BytesBuilder();
        for (var i = 0; i < encrypted.length; i++) {
          out.add(cipher.update(encrypted, i, 1));
        }
        out.add(cipher.doFinal());
        expect(out.takeBytes(), message);
      }
    }
  });
  test('Reject all invalid padding bytes and incomplete unpadded block', () {
    final key = Uint8List(16);
    final malformed = Uint8List(16)
      ..[14] = 1
      ..[15] = 2;
    final cipher = CraftAESCipher(true, key, iv, usePadding: false);
    final encrypted = cipher.update(malformed, 0, 16);
    expect(() => PkiUtils.processAesCbc(false, key, iv, encrypted),
        throwsFormatException);
    final incomplete = CraftAESCipher(false, key, iv, usePadding: false)
      ..update(Uint8List(3), 0, 3);
    expect(incomplete.doFinal, throwsFormatException);
  });
  test('PBKDF2-HMAC-SHA256 published vectors', () {
    expect(
        PkiUtils.deriveKey(
            'password', Uint8List.fromList(utf8.encode('salt')), 1),
        hex('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b'));
    expect(
        PkiUtils.deriveKey(
            'password', Uint8List.fromList(utf8.encode('salt')), 2),
        hex('ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43'));
  });
  test('DER negative integers, large second OID arc, truncation and depth', () {
    for (final value in [-129, -128, -1, 0, 127, 128, 65537]) {
      final encoded = ASN1Integer(BigInt.from(value)).encode();
      expect((ASN1Parser(encoded).nextObject() as ASN1Integer).integer,
          BigInt.from(value));
    }
    final oid = ASN1ObjectIdentifier.fromIdentifierString(
        '2.999.123456789012345678901234567890');
    expect(
        (ASN1Parser(oid.encode()).nextObject() as ASN1ObjectIdentifier)
            .objectIdentifierAsString,
        oid.objectIdentifierAsString);
    for (final data in [
      '3080',
      '308401',
      '0200',
      '030108',
      '050100',
      '060180',
      '30030201'
    ]) {
      expect(() => ASN1Parser(hex(data)).nextObject(), throwsFormatException);
    }
    ASN1Object nested = ASN1Null();
    for (var i = 0; i < 70; i++) {
      nested = ASN1Sequence(elements: [nested]);
    }
    expect(
        () => ASN1Parser(nested.encode()).nextObject(), throwsFormatException);
  });
  test('RSA signatures interoperate in both directions with independent oracle',
      () {
    final pair = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
    final public = pair.publicKey as RSAPublicKey,
        private = pair.privateKey as RSAPrivateKey;
    final pcPublic = oracle.RSAPublicKey(public.modulus, public.exponent);
    final pcPrivate = oracle.RSAPrivateKey(
        private.modulus, private.exponent, private.p, private.q);
    final message =
        Uint8List.fromList(utf8.encode('Independent RSA compatibility'));
    for (final hash in ['SHA-1', 'SHA-256', 'SHA-384', 'SHA-512']) {
      final local = Signer('$hash/RSA')
        ..init(true, PrivateKeyParameter(private));
      final sig = local.generateSignature(message);
      final pc = oracle.Signer('$hash/RSA')
        ..init(false, oracle.PublicKeyParameter<oracle.RSAPublicKey>(pcPublic));
      expect(
          pc.verifySignature(message, oracle.RSASignature(sig.bytes)), isTrue);
      pc.init(
          true, oracle.PrivateKeyParameter<oracle.RSAPrivateKey>(pcPrivate));
      final fromPc = pc.generateSignature(message) as oracle.RSASignature;
      local.init(false, PublicKeyParameter(public));
      expect(
          local.verifySignature(message, RSASignature(fromPc.bytes)), isTrue);
      final changed = Uint8List.fromList(message)..[0] ^= 1;
      expect(
          local.verifySignature(changed, RSASignature(fromPc.bytes)), isFalse);
      expect(local.verifySignature(message, RSASignature(Uint8List(128))),
          isFalse);
      expect(
          local.verifySignature(message, RSASignature(fromPc.bytes.sublist(1))),
          isFalse);
    }
  });
  test('X509 certificate validates signatures, dates and CA fields', () {
    final pair = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
    final certificate = PkiUtils.createCertificate(
        subjectDN: 'CN=Local Root,O=PDF',
        issuerDN: 'CN=Local Root,O=PDF',
        issuerPrivateKey: pair.privateKey as RSAPrivateKey,
        subjectPublicKey: pair.publicKey as RSAPublicKey,
        serialNumber: BigInt.from(42),
        notBefore: DateTime.utc(2020),
        notAfter: DateTime.utc(2070),
        isCa: true);
    final parsed = X509Certificate(certificate);
    expect(parsed.version, 3);
    expect(parsed.isCA(), isTrue);
    expect(parsed.getSubjectDN(), 'CN=Local Root,O=PDF');
    expect(parsed.getNotBefore(), DateTime.utc(2020));
    expect(parsed.getNotAfter(), DateTime.utc(2070));
    parsed.checkValidity(DateTime.utc(2026));
    parsed.verify(parsed.getPublicKey());
    expect(() => parsed.checkValidity(DateTime.utc(2071)), throwsStateError);
    final damaged = Uint8List.fromList(certificate)
      ..[certificate.length - 1] ^= 1;
    expect(() => X509Certificate(damaged).verify(parsed.getPublicKey()),
        throwsFormatException);
  });
}
