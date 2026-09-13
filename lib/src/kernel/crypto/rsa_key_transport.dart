import 'dart:typed_data';

import 'package:dpdf/src/pki/rsa.dart';
import 'package:dpdf/src/sign/der_objects.dart';

/// RSAES-PKCS1-v1_5 key transport, RFC 8017 sections 7.2.1 and 7.2.2.
///
/// Public-key security handlers (ISO 32000-1:2008, 7.6.4) wrap the content
/// encryption key of the CMS enveloped data with the recipient's RSA public
/// key; this is the primitive that performs that wrapping.
class RsaKeyTransport {
  RsaKeyTransport._();

  /// RSAES-PKCS1-V1_5-ENCRYPT: `EM = 0x00 || 0x02 || PS || 0x00 || M`.
  ///
  /// `PS` is at least eight pseudo-random non-zero bytes.
  static Uint8List encrypt(RSAPublicKey key, Uint8List message) {
    final size = (key.modulus.bitLength + 7) ~/ 8;
    if (message.length > size - 11) {
      throw ArgumentError('Message too long for the RSA modulus');
    }
    final padding = Uint8List(size - message.length - 3);
    for (var i = 0; i < padding.length;) {
      final candidates = RsaMath.randomBytes(padding.length - i);
      for (final value in candidates) {
        if (value != 0 && i < padding.length) padding[i++] = value;
      }
    }
    final block = Uint8List(size);
    block[0] = 0x00;
    block[1] = 0x02;
    block.setRange(2, 2 + padding.length, padding);
    block[2 + padding.length] = 0x00;
    block.setRange(3 + padding.length, size, message);
    final m = RsaMath.decode(block);
    if (m >= key.modulus) {
      throw ArgumentError('Encoded message is not smaller than the modulus');
    }
    return RsaMath.encode(m.modPow(key.exponent, key.modulus), size);
  }

  /// RSAES-PKCS1-V1_5-DECRYPT.
  ///
  /// The padding checks are performed without early return so that a malformed
  /// block costs the same as a well-formed one.
  static Uint8List decrypt(RSAPrivateKey key, Uint8List ciphertext) {
    final size = (key.modulus.bitLength + 7) ~/ 8;
    if (ciphertext.length != size || size < 11) {
      throw FormatException('RSA ciphertext has the wrong length');
    }
    final c = RsaMath.decode(ciphertext);
    if (c >= key.modulus) {
      throw FormatException('RSA ciphertext is out of range');
    }
    final block = RsaMath.encode(c.modPow(key.exponent, key.modulus), size);
    var invalid = block[0] ^ 0x00;
    invalid |= block[1] ^ 0x02;
    var separator = -1;
    for (var i = 2; i < size; i++) {
      if (block[i] == 0x00 && separator < 0) separator = i;
    }
    if (separator < 10) invalid |= 1;
    if (invalid != 0) {
      throw FormatException('Invalid RSAES-PKCS1-v1_5 padding');
    }
    return Uint8List.fromList(block.sublist(separator + 1));
  }

  /// Parses a DER `SubjectPublicKeyInfo` holding an `rsaEncryption` key.
  static RSAPublicKey publicKeyFromSubjectPublicKeyInfo(Uint8List encoded) {
    final info = ASN1Parser(encoded).readSingle();
    if (info is! ASN1Sequence || info.elements!.length < 2) {
      throw FormatException('Invalid SubjectPublicKeyInfo');
    }
    final bits = info.elements![1];
    if (bits is! ASN1BitString || bits.unusedBits != 0) {
      throw FormatException('Invalid SubjectPublicKeyInfo bit string');
    }
    final key = ASN1Parser(bits.stringValues).readSingle();
    if (key is! ASN1Sequence || key.elements!.length != 2) {
      throw FormatException('Invalid RSAPublicKey');
    }
    final modulus = key.elements![0];
    final exponent = key.elements![1];
    if (modulus is! ASN1Integer || exponent is! ASN1Integer) {
      throw FormatException('Invalid RSAPublicKey fields');
    }
    return RSAPublicKey(modulus.integer!, exponent.integer!);
  }
}
