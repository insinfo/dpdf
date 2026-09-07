import '../commons/digest/digest_bytes.dart';
import '../kernel/crypto/aes_cipher.dart';
export 'rsa.dart';
import 'dart:typed_data';
import 'dart:convert';

import 'package:dpdf/src/pki/rsa.dart';
import 'package:dpdf/src/sign/asn1_utils.dart' as DpdfAsn1;
import 'package:dpdf/src/sign/der_objects.dart';

class PkiUtils {
  static Uint8List generateRandomBytes(int length) =>
      RsaMath.randomBytes(length);

  static AsymmetricKeyPair<PublicKey, PrivateKey> generateRSAKeyPair(
          {int bitStrength = 2048}) =>
      RsaMath.generate(bitStrength);

  /// Creates a basic X.509 v3 certificate.
  ///
  /// The certificate is encoded using the local DER value model.
  static Uint8List createCertificate({
    required String subjectDN,
    required String issuerDN,
    required RSAPrivateKey issuerPrivateKey,
    required RSAPublicKey subjectPublicKey,
    required BigInt serialNumber,
    required DateTime notBefore,
    required DateTime notAfter,
    bool isCa = false,
  }) {
    // 1. Build TBSCertificate
    final tbs = _buildTBSCertificate(
      subjectDN: subjectDN,
      issuerDN: issuerDN,
      subjectPublicKey: subjectPublicKey,
      serialNumber: serialNumber,
      notBefore: notBefore,
      notAfter: notAfter,
      isCa: isCa,
    );

    // 2. Sign TBSCertificate
    final signature = _signData(tbs, issuerPrivateKey);

    // 3. Construct Certificate Sequence
    final certSeq = ASN1Sequence();
    certSeq.add(ASN1Parser(tbs).nextObject()); // Add TBS (re-parsed to object)

    // Signature Algorithm (SHA256withRSA)
    final sigAlg = ASN1Sequence();
    sigAlg.add(
        ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.11'));
    sigAlg.add(ASN1Null());
    certSeq.add(sigAlg);

    // Signature Value
    certSeq.add(ASN1BitString(stringValues: signature));

    return certSeq.encode();
  }

  static Uint8List _buildTBSCertificate({
    required String subjectDN,
    required String issuerDN,
    required RSAPublicKey subjectPublicKey,
    required BigInt serialNumber,
    required DateTime notBefore,
    required DateTime notAfter,
    required bool isCa,
  }) {
    final tbs = ASN1Sequence();

    // Version (v3 = 2)
    // [0] EXPLICIT INTEGER 2
    final versionSeq = ASN1Integer(BigInt.from(2));
    // Explicit tagging wrapper using DpdfAsn1
    tbs.add(ASN1Object.fromBytes(
        DpdfAsn1.ASN1Utils.encodeTagged(0xA0, versionSeq.encode())));

    // Serial Number
    tbs.add(ASN1Integer(serialNumber));

    // Signature Algorithm
    final sigAlg = ASN1Sequence();
    sigAlg.add(
        ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.11'));
    sigAlg.add(ASN1Null());
    tbs.add(sigAlg);

    // Issuer
    tbs.add(_buildName(issuerDN));

    // Validity
    final validity = ASN1Sequence();
    validity.add(ASN1UtcTime(notBefore));
    validity.add(ASN1UtcTime(notAfter));
    tbs.add(validity);

    // Subject
    tbs.add(_buildName(subjectDN));

    // SubjectPublicKeyInfo
    tbs.add(_buildSubjectPublicKeyInfo(subjectPublicKey));

    // Extensions
    final extensions = ASN1Sequence();

    // BasicConstraints
    final basicConstraintsSeq = ASN1Sequence();
    basicConstraintsSeq.add(ASN1Boolean(isCa));
    final basicConstraintsOctet =
        ASN1OctetString(octets: basicConstraintsSeq.encode());

    final basicConstraintExt = ASN1Sequence();
    basicConstraintExt
        .add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.19'));
    basicConstraintExt.add(ASN1Boolean(true)); // Critical
    basicConstraintExt.add(basicConstraintsOctet);
    extensions.add(basicConstraintExt);

    // Add Extensions [3] EXPLICIT
    tbs.add(ASN1Object.fromBytes(
        DpdfAsn1.ASN1Utils.encodeTagged(0xA3, extensions.encode())));

    return tbs.encode();
  }

  static ASN1Sequence _buildName(String dn) {
    // Simplified DN parser/builder: CN=Name,O=Org,C=Country
    final rdnSeq = ASN1Sequence();

    final parts = dn.split(',');
    for (var part in parts) {
      final text = part.trim();
      final kv = text.split('=');
      if (kv.length != 2) continue;

      final key = kv[0].toUpperCase();
      final val = kv[1];

      String oid;
      switch (key) {
        case 'CN':
          oid = '2.5.4.3';
          break;
        case 'C':
          oid = '2.5.4.6';
          break;
        case 'O':
          oid = '2.5.4.10';
          break;
        case 'OU':
          oid = '2.5.4.11';
          break;
        default:
          continue;
      }

      final attrSet = ASN1Set();
      final attrSeq = ASN1Sequence();
      attrSeq.add(ASN1ObjectIdentifier.fromIdentifierString(oid));
      attrSeq.add(ASN1PrintableString(stringValue: val)); // Named parameter
      attrSet.add(attrSeq);
      rdnSeq.add(attrSet);
    }

    return rdnSeq;
  }

  static ASN1Sequence _buildSubjectPublicKeyInfo(RSAPublicKey publicKey) {
    final seq = ASN1Sequence();

    final algId = ASN1Sequence();
    algId
        .add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'));
    algId.add(ASN1Null());
    seq.add(algId);

    final keySeq = ASN1Sequence();
    keySeq.add(ASN1Integer(publicKey.modulus));
    keySeq.add(ASN1Integer(publicKey.exponent));

    seq.add(ASN1BitString(stringValues: keySeq.encode()));

    return seq;
  }

  static Uint8List _signData(Uint8List data, RSAPrivateKey key) {
    final signer = Signer('SHA-256/RSA');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(key));
    final sig = signer.generateSignature(data);
    return sig.bytes;
  }

  static Uint8List deriveKey(String password, Uint8List salt, int iterations) {
    if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');
    var key = Uint8List.fromList(utf8.encode(password));
    if (key.length > 64) key = DigestBytes.compute('SHA256', key);
    final inner = Uint8List(64)..fillRange(0, 64, 0x36);
    final outer = Uint8List(64)..fillRange(0, 64, 0x5c);
    for (var i = 0; i < key.length; i++) {
      inner[i] ^= key[i];
      outer[i] ^= key[i];
    }
    Uint8List hmac(List<int> message) => DigestBytes.compute(
        'SHA256',
        Uint8List.fromList([
          ...outer,
          ...DigestBytes.compute(
              'SHA256', Uint8List.fromList([...inner, ...message]))
        ]));
    var u = hmac([...salt, 0, 0, 0, 1]);
    final result = Uint8List.fromList(u);
    for (var round = 1; round < iterations; round++) {
      u = hmac(u);
      for (var i = 0; i < 32; i++) {
        result[i] ^= u[i];
      }
    }
    return result;
  }

  static Uint8List processAesCbc(
      bool encrypt, Uint8List key, Uint8List iv, Uint8List data) {
    final cipher = AESCipher(encrypt, key, iv);
    return Uint8List.fromList(
        [...cipher.update(data, 0, data.length), ...cipher.doFinal()]);
  }
}
