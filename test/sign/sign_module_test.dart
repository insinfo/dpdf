import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dpdf/src/sign/oid.dart';
import 'package:dpdf/src/sign/signature_mechanisms.dart';
import 'package:dpdf/src/sign/digest_algorithms.dart';
import 'package:dpdf/src/sign/crypto_digest.dart';
import 'package:dpdf/src/sign/access_permissions.dart';
import 'package:dpdf/src/sign/signer_properties.dart';
import 'package:dpdf/src/sign/pdf_pkcs7.dart';
import 'package:dpdf/src/sign/pdf_signer.dart';
import 'package:dpdf/src/sign/i_external_signature_container.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';

void main() {
  group('OID', () {
    test('RSA OIDs are correct', () {
      expect(OID.rsa, equals('1.2.840.113549.1.1.1'));
      expect(OID.rsaSha256, equals('1.2.840.113549.1.1.11'));
      expect(OID.rsaSha384, equals('1.2.840.113549.1.1.12'));
      expect(OID.rsaSha512, equals('1.2.840.113549.1.1.13'));
    });

    test('Hash OIDs are correct', () {
      expect(OID.sha1, equals('1.3.14.3.2.26'));
      expect(OID.sha256, equals('2.16.840.1.101.3.4.2.1'));
      expect(OID.sha384, equals('2.16.840.1.101.3.4.2.2'));
      expect(OID.sha512, equals('2.16.840.1.101.3.4.2.3'));
      expect(OID.md5, equals('1.2.840.113549.2.5'));
    });

    test('EdDSA OIDs are correct', () {
      expect(OID.ed25519, equals('1.3.101.112'));
      expect(OID.ed448, equals('1.3.101.113'));
    });

    test('CMS Content types are correct', () {
      expect(OID.signedData, equals('1.2.840.113549.1.7.2'));
      expect(OID.data, equals('1.2.840.113549.1.7.1'));
    });
  });

  group('SignatureMechanisms', () {
    test('getAlgorithm returns algorithm name for known OID', () {
      expect(SignatureMechanisms.getAlgorithm('1.2.840.113549.1.1.1'),
          equals('RSA'));
      expect(
          SignatureMechanisms.getAlgorithm('1.2.840.10040.4.1'), equals('DSA'));
      expect(SignatureMechanisms.getAlgorithm('1.2.840.10045.2.1'),
          equals('ECDSA'));
      expect(SignatureMechanisms.getAlgorithm(OID.ed25519), equals('Ed25519'));
      expect(SignatureMechanisms.getAlgorithm(OID.ed448), equals('Ed448'));
    });

    test('getAlgorithm returns OID for unknown OID', () {
      expect(
          SignatureMechanisms.getAlgorithm('1.2.3.4.5'), equals('1.2.3.4.5'));
    });

    test('getSignatureMechanismOid for RSA', () {
      expect(SignatureMechanisms.getSignatureMechanismOid('RSA', 'SHA256'),
          equals('1.2.840.113549.1.1.11'));
      expect(SignatureMechanisms.getSignatureMechanismOid('RSA', 'SHA384'),
          equals('1.2.840.113549.1.1.12'));
      expect(SignatureMechanisms.getSignatureMechanismOid('RSA', 'SHA512'),
          equals('1.2.840.113549.1.1.13'));
    });

    test('getSignatureMechanismOid for ECDSA', () {
      expect(SignatureMechanisms.getSignatureMechanismOid('ECDSA', 'SHA256'),
          equals('1.2.840.10045.4.3.2'));
      expect(SignatureMechanisms.getSignatureMechanismOid('ECDSA', 'SHA384'),
          equals('1.2.840.10045.4.3.3'));
    });

    test('getSignatureMechanismOid for EdDSA', () {
      expect(SignatureMechanisms.getSignatureMechanismOid('Ed25519', null),
          equals(OID.ed25519));
      expect(SignatureMechanisms.getSignatureMechanismOid('Ed448', null),
          equals(OID.ed448));
    });

    test('getSignatureMechanismOid for RSASSA-PSS', () {
      expect(
          SignatureMechanisms.getSignatureMechanismOid('RSASSA-PSS', 'SHA256'),
          equals(OID.rsassaPss));
      expect(SignatureMechanisms.getSignatureMechanismOid('RSA/PSS', 'SHA256'),
          equals(OID.rsassaPss));
    });

    test('getMechanism returns correct mechanism name', () {
      expect(SignatureMechanisms.getMechanism('1.2.840.113549.1.1.1', 'SHA256'),
          equals('SHA256withRSA'));
      expect(SignatureMechanisms.getMechanism('1.2.840.10045.2.1', 'SHA256'),
          equals('SHA256withECDSA'));
    });
  });

  group('DigestAlgorithms', () {
    test('algorithm constants', () {
      expect(DigestAlgorithms.sha1, equals('SHA-1'));
      expect(DigestAlgorithms.sha256, equals('SHA-256'));
      expect(DigestAlgorithms.sha384, equals('SHA-384'));
      expect(DigestAlgorithms.sha512, equals('SHA-512'));
    });

    test('getDigest returns name for known OIDs', () {
      expect(DigestAlgorithms.getDigest('1.2.840.113549.2.5'), equals('MD5'));
      expect(DigestAlgorithms.getDigest('1.3.14.3.2.26'), equals('SHA1'));
      expect(DigestAlgorithms.getDigest(OID.sha256), equals('SHA256'));
      expect(DigestAlgorithms.getDigest(OID.sha384), equals('SHA384'));
      expect(DigestAlgorithms.getDigest(OID.sha512), equals('SHA512'));
    });

    test('getAllowedDigest returns OID for known algorithms', () {
      expect(DigestAlgorithms.getAllowedDigest('SHA-256'), equals(OID.sha256));
      expect(DigestAlgorithms.getAllowedDigest('SHA256'), equals(OID.sha256));
      expect(DigestAlgorithms.getAllowedDigest('MD5'),
          equals('1.2.840.113549.2.5'));
    });

    test('getAllowedDigest returns null for unknown algorithms', () {
      expect(DigestAlgorithms.getAllowedDigest('UNKNOWN'), isNull);
    });

    test('getAllowedDigest throws on null', () {
      expect(
          () => DigestAlgorithms.getAllowedDigest(null), throwsArgumentError);
    });

    test('getOutputBitLength returns correct lengths', () {
      expect(DigestAlgorithms.getOutputBitLength('SHA-1'), equals(160));
      expect(DigestAlgorithms.getOutputBitLength('SHA-256'), equals(256));
      expect(DigestAlgorithms.getOutputBitLength('SHA-384'), equals(384));
      expect(DigestAlgorithms.getOutputBitLength('SHA-512'), equals(512));
      expect(DigestAlgorithms.getOutputBitLength('MD5'), equals(128));
    });

    test('getOutputBitLength throws on null', () {
      expect(
          () => DigestAlgorithms.getOutputBitLength(null), throwsArgumentError);
    });

    test('getMessageDigest creates working digest', () {
      final md = DigestAlgorithms.getMessageDigest('SHA-256');
      md.update(Uint8List.fromList([1, 2, 3, 4, 5]));
      final result = md.digest();
      expect(result.length, equals(32));
    });

    test('digestBytes creates correct SHA-256 hash', () {
      final data = Uint8List.fromList([0x61, 0x62, 0x63]); // "abc"
      final hash = DigestAlgorithms.digestBytes(data, 'SHA-256');
      // Known SHA-256 of "abc"
      expect(hash.length, equals(32));
      expect(hash[0], equals(0xba));
      expect(hash[1], equals(0x78));
    });
  });

  group('CryptoDigest', () {
    test('SHA-256 produces correct output length', () {
      final digest = CryptoDigest();
      final md = digest.getMessageDigest('SHA-256');
      md.update(Uint8List.fromList([1, 2, 3]));
      final result = md.digest();
      expect(result.length, equals(32));
    });

    test('SHA-1 produces correct output length', () {
      final digest = CryptoDigest();
      final md = digest.getMessageDigest('SHA-1');
      md.update(Uint8List.fromList([1, 2, 3]));
      final result = md.digest();
      expect(result.length, equals(20));
    });

    test('SHA-384 produces correct output length', () {
      final digest = CryptoDigest();
      final md = digest.getMessageDigest('SHA-384');
      md.update(Uint8List.fromList([1, 2, 3]));
      final result = md.digest();
      expect(result.length, equals(48));
    });

    test('SHA-512 produces correct output length', () {
      final digest = CryptoDigest();
      final md = digest.getMessageDigest('SHA-512');
      md.update(Uint8List.fromList([1, 2, 3]));
      final result = md.digest();
      expect(result.length, equals(64));
    });

    test('MD5 produces correct output length', () {
      final digest = CryptoDigest();
      final md = digest.getMessageDigest('MD5');
      md.update(Uint8List.fromList([1, 2, 3]));
      final result = md.digest();
      expect(result.length, equals(16));
    });

    test('reset clears buffer', () {
      final md = CryptoMessageDigest.sha256();
      md.update(Uint8List.fromList([1, 2, 3]));
      md.reset();
      md.update(Uint8List.fromList([4, 5, 6]));
      final result = md.digest();
      // Should only contain digest of [4, 5, 6]
      expect(result.length, equals(32));
    });

    test('throws on unsupported algorithm', () {
      final digest = CryptoDigest();
      expect(() => digest.getMessageDigest('UNKNOWN'), throwsUnsupportedError);
    });
  });

  group('AccessPermissions', () {
    test('enum values exist', () {
      expect(AccessPermissions.values.length, equals(4));
      expect(AccessPermissions.unspecified, isNotNull);
      expect(AccessPermissions.noChangesPermitted, isNotNull);
      expect(AccessPermissions.formFieldsModification, isNotNull);
      expect(AccessPermissions.annotationModification, isNotNull);
    });
  });

  group('SignerProperties', () {
    test('default values', () {
      final props = SignerProperties();
      expect(props.getPageNumber(), equals(1));
      expect(
          props.getCertificationLevel(), equals(AccessPermissions.unspecified));
      expect(props.getSignatureCreator(), equals(''));
      expect(props.getContact(), equals(''));
      expect(props.getReason(), equals(''));
      expect(props.getLocation(), equals(''));
      expect(props.getFieldName(), isNull);
    });

    test('fluent setters', () {
      final props = SignerProperties()
          .setFieldName('Signature1')
          .setPageNumber(2)
          .setReason('Testing')
          .setLocation('Test Location')
          .setContact('test@example.com')
          .setSignatureCreator('TestApp')
          .setCertificationLevel(AccessPermissions.noChangesPermitted);

      expect(props.getFieldName(), equals('Signature1'));
      expect(props.getPageNumber(), equals(2));
      expect(props.getReason(), equals('Testing'));
      expect(props.getLocation(), equals('Test Location'));
      expect(props.getContact(), equals('test@example.com'));
      expect(props.getSignatureCreator(), equals('TestApp'));
      expect(props.getCertificationLevel(),
          equals(AccessPermissions.noChangesPermitted));
    });

    test('setPageRect', () {
      final rect = Rectangle(10, 20, 100, 50);
      final props = SignerProperties().setPageRect(rect);
      final result = props.getPageRect();
      expect(result.getX(), equals(10));
      expect(result.getY(), equals(20));
      expect(result.getWidth(), equals(100));
      expect(result.getHeight(), equals(50));
    });

    test('setClaimedSignDate', () {
      final date = DateTime(2025, 12, 25, 10, 30);
      final props = SignerProperties().setClaimedSignDate(date);
      expect(props.getClaimedSignDate(), equals(date));
    });

    test('setFieldName with null does not change value', () {
      final props = SignerProperties().setFieldName('Sig1').setFieldName(null);
      expect(props.getFieldName(), equals('Sig1'));
    });
  });

  group('PdfPKCS7', () {
    test('forVerifying constructor stores signature value', () {
      final pkcs7 = PdfPKCS7.forVerifying(
        Uint8List.fromList([1, 2, 3, 4]),
        PdfName.etsiCadesDetached,
      );
      expect(pkcs7.getFilterSubtype(), equals(PdfName.etsiCadesDetached));
    });

    test('forRsaSha1 constructor sets correct OIDs', () {
      final pkcs7 = PdfPKCS7.forRsaSha1(
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5, 6]),
      );
      expect(pkcs7.getDigestAlgorithmOid(), equals('1.2.840.10040.4.3'));
      expect(pkcs7.getSignatureMechanismOid(), equals('1.3.36.3.3.1.2'));
    });

    test('sign properties work correctly', () {
      final now = DateTime.now();
      final pkcs7 = PdfPKCS7.forVerifying(
        Uint8List.fromList([1, 2, 3, 4]),
        PdfName.etsiCadesDetached,
      )
        ..setSignName('Test Signer')
        ..setReason('Testing')
        ..setLocation('Test Location')
        ..setSignDate(now);

      expect(pkcs7.getSignName(), equals('Test Signer'));
      expect(pkcs7.getReason(), equals('Testing'));
      expect(pkcs7.getLocation(), equals('Test Location'));
      expect(pkcs7.getSignDate(), equals(now));
    });

    test('setExternalSignatureValue updates signature', () {
      final pkcs7 = PdfPKCS7.forVerifying(
        Uint8List.fromList([1, 2, 3, 4]),
        PdfName.adbePkcs7Detached,
      );

      pkcs7.setExternalSignatureValue(
        Uint8List.fromList([10, 20, 30]),
        Uint8List.fromList([40, 50, 60]),
        null,
      );

      // Should be able to get encoded PKCS#1
      expect(pkcs7.getEncodedPKCS1(), equals(Uint8List.fromList([10, 20, 30])));
    });

    test('getVersion returns default version', () {
      final pkcs7 = PdfPKCS7.forVerifying(
        Uint8List.fromList([1, 2, 3, 4]),
        PdfName.adbePkcs7Detached,
      );
      expect(pkcs7.getVersion(), equals(1));
      expect(pkcs7.getSigningInfoVersion(), equals(1));
    });

    test('getSignatureMechanismName returns correct name for Ed25519', () {
      final pkcs7 = PdfPKCS7.forVerifying(
        Uint8List.fromList([1, 2, 3, 4]),
        PdfName.adbePkcs7Detached,
      );
      // When mechanism OID is null, should return default
      expect(pkcs7.getSignatureMechanismName(), equals('SHA256withRSA'));
    });

    test('getCertificates returns empty list initially', () {
      final pkcs7 = PdfPKCS7.forVerifying(
        Uint8List.fromList([1, 2, 3, 4]),
        PdfName.adbePkcs7Detached,
      );
      expect(pkcs7.getCertificates(), isEmpty);
      expect(pkcs7.getSigningCertificate(), isNull);
    });
  });

  group('PdfSigner', () {
    test('getSignerProperties returns properties', () async {
      final signer = await PdfSigner.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        MockSink(),
      );

      expect(signer.getSignerProperties(), isNotNull);
    });

    test('setSignerProperties updates properties', () async {
      final signer = await PdfSigner.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        MockSink(),
      );

      final props =
          SignerProperties().setFieldName('TestSig').setReason('Testing');

      signer.setSignerProperties(props);
      expect(signer.getFieldName(), equals('TestSig'));
      expect(signer.getReason(), equals('Testing'));
    });

    test('fluent setters work correctly', () async {
      final signer = await PdfSigner.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        MockSink(),
      );

      signer.setFieldName('Signature1');
      signer.setPageNumber(2);
      signer.setReason('Test reason');
      signer.setLocation('Test location');
      signer.setContact('test@example.com');
      signer.setSignatureCreator('TestApp');

      expect(signer.getFieldName(), equals('Signature1'));
      expect(signer.getPageNumber(), equals(2));
      expect(signer.getReason(), equals('Test reason'));
      expect(signer.getLocation(), equals('Test location'));
      expect(signer.getContact(), equals('test@example.com'));
      expect(signer.getSignatureCreator(), equals('TestApp'));
    });

    test('getNewSigFieldName returns default name', () async {
      final signer = await PdfSigner.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        MockSink(),
      );

      final name = await signer.getNewSigFieldName();
      expect(name, equals('Signature1'));
    });

    test('close prevents further operations', () async {
      final signer = await PdfSigner.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        MockSink(),
      );

      await signer.close();

      expect(
        () async => await signer.signExternalContainer(MockContainer(), 8192),
        throwsStateError,
      );
    });
  });
}

// Mock classes for testing
class MockSink implements Sink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void close() {}
}

class MockContainer implements IExternalSignatureContainer {
  @override
  Future<Uint8List> sign(Stream<List<int>> data) async {
    return Uint8List(0);
  }

  @override
  void modifySigningDictionary(PdfDictionary signDic) {}
}
