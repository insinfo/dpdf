import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/pki/pki_utils.dart';
import 'package:dpdf/src/sign/der_objects.dart';
import 'package:dpdf/src/sign/asn1_utils.dart';
import 'package:dpdf/src/sign/x509_certificate.dart';
import 'package:dpdf/src/sign/pdf_pkcs7.dart';
import 'package:dpdf/src/sign/oid.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/commons/digest/digest_bytes.dart';

void main() {
  late RSAPrivateKey key;
  late X509Certificate certificate;
  final document =
      Uint8List.fromList('%PDF synthetic covered ranges'.codeUnits);
  ASN1Object oid(String value) =>
      ASN1ObjectIdentifier.fromIdentifierString(value);
  ASN1Sequence algorithm(String value) =>
      ASN1Sequence(elements: [oid(value), ASN1Null()]);
  setUpAll(() {
    final pair = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
    key = pair.privateKey as RSAPrivateKey;
    certificate = X509Certificate(PkiUtils.createCertificate(
        subjectDN: 'CN=Legacy test',
        issuerDN: 'CN=Legacy test',
        issuerPrivateKey: key,
        subjectPublicKey: pair.publicKey as RSAPublicKey,
        serialNumber: BigInt.from(12),
        notBefore: DateTime.utc(2020),
        notAfter: DateTime.utc(2030)));
  });
  Uint8List build(
      {bool attributes = true,
      bool wrongDigest = false,
      bool omitContent = false,
      bool wrongContent = false}) {
    final content = DigestBytes.compute('SHA1', document);
    if (wrongContent) content[0] ^= 1;
    final signedAttributes = ASN1Set(elements: [
      ASN1Sequence(elements: [
        oid(OID.contentType),
        ASN1Set(elements: [oid(OID.data)])
      ]),
      ASN1Sequence(elements: [
        oid(OID.messageDigest),
        ASN1Set(elements: [
          ASN1OctetString(
              octets: DigestBytes.compute(
                  'SHA256', wrongDigest ? document : content))
        ])
      ]),
    ]).encode();
    final signing = Signer('SHA-256/RSA')..init(true, PrivateKeyParameter(key));
    final signature = signing
        .generateSignature(attributes ? signedAttributes : content)
        .bytes;
    final signer = ASN1Sequence(elements: [
      ASN1Integer(BigInt.one),
      ASN1Sequence(elements: [
        ASN1Parser(certificate.getIssuerX500Name()).readSingle(),
        ASN1Integer(BigInt.from(12))
      ]),
      algorithm(OID.sha256),
      if (attributes)
        ASN1Object(0xa0, ASN1Utils.parse(signedAttributes).content),
      algorithm('1.2.840.113549.1.1.11'),
      ASN1OctetString(octets: signature)
    ]);
    final body = ASN1Sequence(elements: [
      ASN1Integer(BigInt.one),
      ASN1Set(elements: [algorithm(OID.sha256)]),
      ASN1Sequence(elements: [
        oid(OID.data),
        if (!omitContent)
          ASN1Sequence(tag: 0xa0, elements: [ASN1OctetString(octets: content)])
      ]),
      ASN1Sequence(
          tag: 0xa0,
          elements: [ASN1Parser(certificate.getEncoded()).readSingle()]),
      ASN1Set(elements: [signer])
    ]);
    return ASN1Sequence(elements: [
      oid(OID.signedData),
      ASN1Sequence(tag: 0xa0, elements: [body])
    ]).encode();
  }

  test(
      'legacy SHA1 content and CMS SHA256 attributes verify in either call order',
      () {
    for (final firstDigest in [false, true]) {
      final check = PdfPKCS7.forVerifying(build(), PdfName.adbePkcs7Sha1)
        ..update(document);
      if (firstDigest) expect(check.verifyDigest(), isTrue);
      expect(check.verify(), isTrue);
      expect(check.verifyDigest(), isTrue);
    }
  });
  test(
      'legacy content without attributes verifies signature over encapsulated hash',
      () {
    final check =
        PdfPKCS7.forVerifying(build(attributes: false), PdfName.adbePkcs7Sha1)
          ..update(document);
    expect(check.verify(), isTrue);
  });
  test(
      'legacy rejects tampered ranges, wrong encapsulated hash and wrong attribute digest',
      () {
    for (final bytes in [
      build(wrongDigest: true),
      build(wrongContent: true),
      build(omitContent: true),
      build(omitContent: true, wrongDigest: true)
    ]) {
      final check = PdfPKCS7.forVerifying(bytes, PdfName.adbePkcs7Sha1)
        ..update(document);
      expect(check.verifyDigest(), isFalse);
      expect(check.verify(), isFalse);
    }
    final altered = Uint8List.fromList(document)..[0] ^= 1;
    for (final attrs in [false, true]) {
      final check =
          PdfPKCS7.forVerifying(build(attributes: attrs), PdfName.adbePkcs7Sha1)
            ..update(altered);
      expect(check.verify(), isFalse);
    }
  });
}
