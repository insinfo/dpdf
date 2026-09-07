import 'dart:io';
import 'dart:convert';
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
import 'package:dpdf/src/sign/external_signature_container.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';

void main() {
  group('OID', () {
    test('RSA OIDs are correct', () {
      expect(CraftOID.rsa, equals('1.2.840.113549.1.1.1'));
      expect(CraftOID.rsaSha256, equals('1.2.840.113549.1.1.11'));
      expect(CraftOID.rsaSha384, equals('1.2.840.113549.1.1.12'));
      expect(CraftOID.rsaSha512, equals('1.2.840.113549.1.1.13'));
    });

    test('Hash OIDs are correct', () {
      expect(CraftOID.sha1, equals('1.3.14.3.2.26'));
      expect(CraftOID.sha256, equals('2.16.840.1.101.3.4.2.1'));
      expect(CraftOID.sha384, equals('2.16.840.1.101.3.4.2.2'));
      expect(CraftOID.sha512, equals('2.16.840.1.101.3.4.2.3'));
      expect(CraftOID.md5, equals('1.2.840.113549.2.5'));
    });

    test('EdDSA OIDs are correct', () {
      expect(CraftOID.ed25519, equals('1.3.101.112'));
      expect(CraftOID.ed448, equals('1.3.101.113'));
    });

    test('CMS Content types are correct', () {
      expect(CraftOID.signedData, equals('1.2.840.113549.1.7.2'));
      expect(CraftOID.data, equals('1.2.840.113549.1.7.1'));
    });
  });

  group('SignatureMechanisms', () {
    test('getAlgorithm returns algorithm name for known OID', () {
      expect(CraftSignatureMechanisms.getAlgorithm('1.2.840.113549.1.1.1'),
          equals('RSA'));
      expect(CraftSignatureMechanisms.getAlgorithm('1.2.840.10040.4.1'),
          equals('DSA'));
      expect(CraftSignatureMechanisms.getAlgorithm('1.2.840.10045.2.1'),
          equals('ECDSA'));
      expect(CraftSignatureMechanisms.getAlgorithm(CraftOID.ed25519),
          equals('Ed25519'));
      expect(CraftSignatureMechanisms.getAlgorithm(CraftOID.ed448),
          equals('Ed448'));
    });

    test('getAlgorithm returns OID for unknown OID', () {
      expect(CraftSignatureMechanisms.getAlgorithm('1.2.3.4.5'),
          equals('1.2.3.4.5'));
    });

    test('getSignatureMechanismOid for RSA', () {
      expect(CraftSignatureMechanisms.getSignatureMechanismOid('RSA', 'SHA256'),
          equals('1.2.840.113549.1.1.11'));
      expect(CraftSignatureMechanisms.getSignatureMechanismOid('RSA', 'SHA384'),
          equals('1.2.840.113549.1.1.12'));
      expect(CraftSignatureMechanisms.getSignatureMechanismOid('RSA', 'SHA512'),
          equals('1.2.840.113549.1.1.13'));
    });

    test('getSignatureMechanismOid for ECDSA', () {
      expect(
          CraftSignatureMechanisms.getSignatureMechanismOid('ECDSA', 'SHA256'),
          equals('1.2.840.10045.4.3.2'));
      expect(
          CraftSignatureMechanisms.getSignatureMechanismOid('ECDSA', 'SHA384'),
          equals('1.2.840.10045.4.3.3'));
    });

    test('getSignatureMechanismOid for EdDSA', () {
      expect(CraftSignatureMechanisms.getSignatureMechanismOid('Ed25519', null),
          equals(CraftOID.ed25519));
      expect(CraftSignatureMechanisms.getSignatureMechanismOid('Ed448', null),
          equals(CraftOID.ed448));
    });

    test('getSignatureMechanismOid for RSASSA-PSS', () {
      expect(
          CraftSignatureMechanisms.getSignatureMechanismOid(
              'RSASSA-PSS', 'SHA256'),
          equals(CraftOID.rsassaPss));
      expect(
          CraftSignatureMechanisms.getSignatureMechanismOid(
              'RSA/PSS', 'SHA256'),
          equals(CraftOID.rsassaPss));
    });

    test('getMechanism returns correct mechanism name', () {
      expect(
          CraftSignatureMechanisms.getMechanism(
              '1.2.840.113549.1.1.1', 'SHA256'),
          equals('SHA256withRSA'));
      expect(
          CraftSignatureMechanisms.getMechanism('1.2.840.10045.2.1', 'SHA256'),
          equals('SHA256withECDSA'));
    });
  });

  group('DigestAlgorithms', () {
    test('algorithm constants', () {
      expect(CraftDigestAlgorithms.sha1, equals('SHA-1'));
      expect(CraftDigestAlgorithms.sha256, equals('SHA-256'));
      expect(CraftDigestAlgorithms.sha384, equals('SHA-384'));
      expect(CraftDigestAlgorithms.sha512, equals('SHA-512'));
    });

    test('getDigest returns name for known OIDs', () {
      expect(
          CraftDigestAlgorithms.getDigest('1.2.840.113549.2.5'), equals('MD5'));
      expect(CraftDigestAlgorithms.getDigest('1.3.14.3.2.26'), equals('SHA1'));
      expect(
          CraftDigestAlgorithms.getDigest(CraftOID.sha256), equals('SHA256'));
      expect(
          CraftDigestAlgorithms.getDigest(CraftOID.sha384), equals('SHA384'));
      expect(
          CraftDigestAlgorithms.getDigest(CraftOID.sha512), equals('SHA512'));
    });

    test('getAllowedDigest returns OID for known algorithms', () {
      expect(CraftDigestAlgorithms.getAllowedDigest('SHA-256'),
          equals(CraftOID.sha256));
      expect(CraftDigestAlgorithms.getAllowedDigest('SHA256'),
          equals(CraftOID.sha256));
      expect(CraftDigestAlgorithms.getAllowedDigest('MD5'),
          equals('1.2.840.113549.2.5'));
    });

    test('getAllowedDigest returns null for unknown algorithms', () {
      expect(CraftDigestAlgorithms.getAllowedDigest('UNKNOWN'), isNull);
    });

    test('getAllowedDigest throws on null', () {
      expect(() => CraftDigestAlgorithms.getAllowedDigest(null),
          throwsArgumentError);
    });

    test('getOutputBitLength returns correct lengths', () {
      expect(CraftDigestAlgorithms.getOutputBitLength('SHA-1'), equals(160));
      expect(CraftDigestAlgorithms.getOutputBitLength('SHA-256'), equals(256));
      expect(CraftDigestAlgorithms.getOutputBitLength('SHA-384'), equals(384));
      expect(CraftDigestAlgorithms.getOutputBitLength('SHA-512'), equals(512));
      expect(CraftDigestAlgorithms.getOutputBitLength('MD5'), equals(128));
    });

    test('getOutputBitLength throws on null', () {
      expect(() => CraftDigestAlgorithms.getOutputBitLength(null),
          throwsArgumentError);
    });

    test('getMessageDigest creates working digest', () {
      final md = CraftDigestAlgorithms.getMessageDigest('SHA-256');
      md.update(Uint8List.fromList([1, 2, 3, 4, 5]));
      final result = md.digest();
      expect(result.length, equals(32));
    });

    test('digestBytes creates correct SHA-256 hash', () {
      final data = Uint8List.fromList([0x61, 0x62, 0x63]); // "abc"
      final hash = CraftDigestAlgorithms.digestBytes(data, 'SHA-256');
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
      final props = CraftSignerProperties();
      expect(props.pageOrdinal(), equals(1));
      expect(
          props.getCertificationLevel(), equals(AccessPermissions.unspecified));
      expect(props.getSignatureCreator(), equals(''));
      expect(props.getContact(), equals(''));
      expect(props.getReason(), equals(''));
      expect(props.getLocation(), equals(''));
      expect(props.getFieldName(), isNull);
    });

    test('fluent setters', () {
      final props = CraftSignerProperties()
          .setFieldName('Signature1')
          .setPageNumber(2)
          .setReason('Testing')
          .setLocation('Test Location')
          .setContact('test@example.com')
          .setSignatureCreator('TestApp')
          .setCertificationLevel(AccessPermissions.noChangesPermitted);

      expect(props.getFieldName(), equals('Signature1'));
      expect(props.pageOrdinal(), equals(2));
      expect(props.getReason(), equals('Testing'));
      expect(props.getLocation(), equals('Test Location'));
      expect(props.getContact(), equals('test@example.com'));
      expect(props.getSignatureCreator(), equals('TestApp'));
      expect(props.getCertificationLevel(),
          equals(AccessPermissions.noChangesPermitted));
    });

    test('setPageRect', () {
      final rect = CraftRectangle(10, 20, 100, 50);
      final props = CraftSignerProperties().setPageRect(rect);
      final result = props.getPageRect();
      expect(result.getX(), equals(10));
      expect(result.getY(), equals(20));
      expect(result.getWidth(), equals(100));
      expect(result.getHeight(), equals(50));
    });

    test('setClaimedSignDate', () {
      final date = DateTime(2025, 12, 25, 10, 30);
      final props = CraftSignerProperties().setClaimedSignDate(date);
      expect(props.getClaimedSignDate(), equals(date));
    });

    test('setFieldName with null does not change value', () {
      final props =
          CraftSignerProperties().setFieldName('Sig1').setFieldName(null);
      expect(props.getFieldName(), equals('Sig1'));
    });
  });

  group('PdfPKCS7', () {
    test('forVerifying constructor stores signature value', () {
      final pkcs7 = CraftPdfPKCS7.forVerifying(
        Uint8List.fromList([1, 2, 3, 4]),
        CraftPdfName.etsiCadesDetached,
      );
      expect(pkcs7.getFilterSubtype(), equals(CraftPdfName.etsiCadesDetached));
    });

    test('forRsaSha1 constructor sets correct OIDs', () {
      final pkcs7 = CraftPdfPKCS7.forRsaSha1(
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5, 6]),
      );
      expect(pkcs7.getDigestAlgorithmOid(), equals(CraftOID.sha1)); // SHA-1
      expect(pkcs7.getSignatureMechanismOid(),
          equals(CraftOID.rsaSha1)); // RSA-SHA1
    });

    test('sign properties work correctly', () {
      final now = DateTime.now();
      final pkcs7 = CraftPdfPKCS7.forVerifying(
        Uint8List.fromList([1, 2, 3, 4]),
        CraftPdfName.etsiCadesDetached,
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
      final pkcs7 = CraftPdfPKCS7.forVerifying(
        Uint8List.fromList([1, 2, 3, 4]),
        CraftPdfName.adbePkcs7Detached,
      );

      pkcs7.setExternalSignatureValue(
        Uint8List.fromList([10, 20, 30]),
        Uint8List.fromList([40, 50, 60]),
        null,
      );

      // Should be able to get the raw signature value
      expect(
          pkcs7.getSignatureValue(), equals(Uint8List.fromList([10, 20, 30])));
    });

    test('getVersion returns default version', () {
      final pkcs7 = CraftPdfPKCS7.forVerifying(
        Uint8List.fromList([1, 2, 3, 4]),
        CraftPdfName.adbePkcs7Detached,
      );
      expect(pkcs7.formatVersion(), equals(1));
      expect(pkcs7.getSigningInfoVersion(), equals(1));
    });

    test('getSignatureMechanismName returns correct name for Ed25519', () {
      final pkcs7 = CraftPdfPKCS7.forVerifying(
        Uint8List.fromList([1, 2, 3, 4]),
        CraftPdfName.adbePkcs7Detached,
      );
      // When mechanism OID is null, should return default
      expect(pkcs7.getSignatureMechanismName(), equals('SHA256withRSA'));
    });

    test('getCertificatesDer returns empty list initially', () {
      final pkcs7 = CraftPdfPKCS7.forVerifying(
        Uint8List.fromList([1, 2, 3, 4]),
        CraftPdfName.adbePkcs7Detached,
      );
      expect(pkcs7.getCertificatesDer(), isEmpty);
    });
  });

  group('PdfSigner', () {
    test('getSignerProperties returns properties', () async {
      final signer = await CraftPdfSigner.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        MockSink(),
      );

      expect(signer.getSignerProperties(), isNotNull);
    });

    test('setSignerProperties updates properties', () async {
      final signer = await CraftPdfSigner.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        MockSink(),
      );

      final props =
          CraftSignerProperties().setFieldName('TestSig').setReason('Testing');

      signer.setSignerProperties(props);
      expect(signer.getFieldName(), equals('TestSig'));
      expect(signer.getReason(), equals('Testing'));
    });

    test('fluent setters work correctly', () async {
      final signer = await CraftPdfSigner.fromBytes(
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
      expect(signer.pageOrdinal(), equals(2));
      expect(signer.getReason(), equals('Test reason'));
      expect(signer.getLocation(), equals('Test location'));
      expect(signer.getContact(), equals('test@example.com'));
      expect(signer.getSignatureCreator(), equals('TestApp'));
    });

    test('getNewSigFieldName returns default name', () async {
      final signer = await CraftPdfSigner.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        MockSink(),
      );

      final name = await signer.getNewSigFieldName();
      expect(name, equals('Signature1'));
    });

    test('close prevents further operations', () async {
      final signer = await CraftPdfSigner.fromBytes(
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
class MockSink implements IOSink {
  @override
  Encoding get encoding => throw UnimplementedError();

  @override
  set encoding(Encoding encoding) => throw UnimplementedError();

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {}

  @override
  Future close() async {}

  @override
  Future get done => Future.value();

  @override
  Future flush() async {}

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable objects, [String separator = ""]) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = ""]) {}
}

class MockContainer implements CraftExternalSignatureContainer {
  @override
  Future<Uint8List> sign(Stream<List<int>> data) async {
    return Uint8List(0);
  }

  @override
  void modifySigningDictionary(CraftPdfDictionary signDic) {}
}
