import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:pointycastle/export.dart';
import 'package:dpdf/src/sign/asn1_utils.dart' as DpdfAsn1;
import 'package:pointycastle/asn1.dart';

class PkiUtils {
  static final SecureRandom _secureRandom = _initSecureRandom();

  static SecureRandom _initSecureRandom() {
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = <int>[];
    for (int i = 0; i < 32; i++) {
      seeds.add(seedSource.nextInt(255));
    }
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  static Uint8List generateRandomBytes(int length) {
    return _secureRandom.nextBytes(length);
  }

  static AsymmetricKeyPair<PublicKey, PrivateKey> generateRSAKeyPair(
      {int bitStrength = 2048}) {
    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), bitStrength, 64),
          _secureRandom));
    return keyGen.generateKeyPair();
  }

  /// Creates a basic X.509 v3 certificate.
  ///
  /// Note: This is a manual ASN.1 construction as PointyCastle lacks a high-level builder.
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
    if (sig is RSASignature) {
      return sig.bytes;
    }
    return Uint8List(0);
  }

  static Uint8List deriveKey(String password, Uint8List salt, int iterations) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    derivator.init(Pbkdf2Parameters(salt, iterations, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  static Uint8List processAesCbc(
      bool encrypt, Uint8List key, Uint8List iv, Uint8List data) {
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      encrypt,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), iv),
        null, // No AAD for basic AES-CBC
      ),
    );
    return cipher.process(data);
  }
}
