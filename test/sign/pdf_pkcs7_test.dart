import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:pdfcraft/src/sign/pdf_pkcs7.dart';

import 'package:pdfcraft/src/sign/external_digest.dart';

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

    // Add more tests as we have mocks for Certificates and Keys
  });
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
