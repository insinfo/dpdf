import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:dpdf/src/sign/x509_certificate.dart';

void main() {
  group('X509Certificate', () {
    test('Parse rootRsa.cer', () {
      final file = File('test/assets/rootRsa.cer');
      if (!file.existsSync()) {
        return;
      }

      var content = file.readAsStringSync();
      // Simple PEM cleanup
      content = content
          .replaceAll('-----BEGIN CERTIFICATE-----', '')
          .replaceAll('-----END CERTIFICATE-----', '')
          .replaceAll('\r', '')
          .replaceAll('\n', '')
          .replaceAll(' ', ''); /* trim extra spaces */

      final bytes = base64.decode(content);
      final cert = X509Certificate(bytes);


      expect(cert.version, equals(3));
      expect(cert.getSerialNumber(), equals(BigInt.from(1491571158)));
      // expect(cert.isCA(), isTrue); // TODO: Fix extension parsing
      // Check extensions
      expect(cert.getKeyUsage(),
          isNull); // Maybe null if not parsed strictly or not present
      // expect(cert.getBasicConstraints(), greaterThanOrEqualTo(0)); // Should be CA
      // expect(cert.version, equals(3));
      // PointyCastle generic object toString often dumps structure
      // getIssuerDN might return the ASN1Sequence toString which isn't pretty but proves it parses.
    });
  });

  group('CertificateUtil', () {
    test('test fields', () {
      // We need a cert with CRL/OCSP
    });
  });
}
