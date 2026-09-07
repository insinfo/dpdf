import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dpdf/src/sign/pdf_pkcs7.dart';

import 'package:dpdf/src/sign/external_digest.dart';
import 'package:dpdf/src/sign/tsa_client.dart';
import 'package:dpdf/src/sign/digest_algorithms.dart';
import 'package:dpdf/src/sign/asn1_utils.dart';
import 'package:dpdf/src/pki/pki_utils.dart';
import 'package:dpdf/src/pki/rsa.dart' as rsa;

void main() {
  group('PdfPKCS7', () {
    test('forSigning throws on unknown hash algorithm', () {
      expect(
        () => CraftPdfPKCS7.forSigning(
          null,
          [],
          'UNKNOWN-HASH',
          MockExternalDigest(),
        ),
        throwsArgumentError,
      );
    });

    test('forSigning creates instance with valid parameters', () {
      // Mock needs to return valid OID for algorithm
      final pkcs7 = CraftPdfPKCS7.forSigning(
        null,
        [],
        'SHA-256',
        MockExternalDigest(),
      );

      expect(pkcs7.getDigestAlgorithmName(), 'SHA256');
      expect(pkcs7.formatVersion(), 1);
    });

    test('timestamps the digest of the signature value', () async {
      final keys = PkiUtils.generateRSAKeyPair(bitStrength: 512);
      final now = DateTime.utc(2026, 1, 1);
      final certificate = PkiUtils.createCertificate(
        subjectDN: 'CN=Timestamp test',
        issuerDN: 'CN=Timestamp test',
        issuerPrivateKey: keys.privateKey as rsa.RSAPrivateKey,
        subjectPublicKey: keys.publicKey as rsa.RSAPublicKey,
        serialNumber: BigInt.one,
        notBefore: now,
        notAfter: now.add(const Duration(days: 1)),
        isCa: false,
      );
      final signature = Uint8List.fromList([1, 2, 3, 4]);
      final tsa = _RecordingTsaClient();
      final pkcs7 = CraftPdfPKCS7.forSigning(
        null,
        [certificate],
        'SHA-256',
        MockExternalDigest(),
      );
      pkcs7.setExternalSignatureValue(signature, null, 'RSA');

      await pkcs7.getEncodedPKCS7(Uint8List(32), tsaClient: tsa);

      expect(
          tsa.imprint, CraftDigestAlgorithms.digestBytes(signature, 'SHA-256'));
    });

    // Add more tests as we have mocks for Certificates and Keys
  });
}

class _RecordingTsaClient implements CraftTSAClient {
  Uint8List? imprint;

  @override
  int getTokenSizeEstimate() => 128;

  @override
  SigningDigest getMessageDigest() =>
      CraftDigestAlgorithms.getMessageDigest('SHA-256');

  @override
  Future<Uint8List> getTimeStampToken(Uint8List value) async {
    imprint = Uint8List.fromList(value);
    return ASN1Utils.createSequence([
      ASN1Utils.createOID('1.2.840.113549.1.7.2'),
      ASN1Utils.encodeTagged(0xa0, ASN1Utils.createSequence([])),
    ]);
  }
}

class MockExternalDigest implements CraftExternalDigest {
  @override
  SigningDigest getMessageDigest(String hashAlgorithm) {
    return MockMessageDigest(hashAlgorithm);
  }
}

class MockMessageDigest implements SigningDigest {
  final String algo;
  MockMessageDigest(this.algo);

  @override
  void update(Uint8List input, [int offset = 0, int? length]) {}

  @override
  Uint8List digest() => Uint8List(32);

  @override
  String getAlgorithmName() => algo;

  @override
  int getDigestSize() => 32;

  @override
  void reset() {}
}
