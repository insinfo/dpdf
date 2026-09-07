import 'dart:convert';
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
import 'package:dpdf/src/kernel/crypto/aes_cipher.dart';

void main() {
  late RSAPrivateKey private;
  late X509Certificate certificate;
  final serial = (BigInt.one << 100) + BigInt.from(7);
  final message = Uint8List.fromList(ascii.encode('document bytes'));
  ASN1Object oid(String value) =>
      ASN1ObjectIdentifier.fromIdentifierString(value);
  ASN1Sequence algorithm(String value) =>
      ASN1Sequence(elements: [oid(value), ASN1Null()]);
  setUpAll(() {
    final pair = PkiUtils.generateRSAKeyPair(bitStrength: 1024);
    private = pair.privateKey as RSAPrivateKey;
    certificate = X509Certificate(PkiUtils.createCertificate(
        subjectDN: 'CN=Verification test',
        issuerDN: 'CN=Verification test',
        issuerPrivateKey: private,
        subjectPublicKey: pair.publicKey as RSAPublicKey,
        serialNumber: serial,
        notBefore: DateTime.utc(2020),
        notAfter: DateTime.utc(2030)));
  });
  Uint8List cms(
      {String mechanism = '1.2.840.113549.1.1.11',
      BigInt? claimedSerial,
      bool encapsulated = false,
      bool omitDigest = false,
      bool duplicateDigest = false,
      bool omitContentType = false}) {
    final attrs = <ASN1Object>[];
    if (!omitContentType) {
      attrs.add(ASN1Sequence(elements: [
        oid(CraftOID.contentType),
        ASN1Set(elements: [oid(CraftOID.data)])
      ]));
    }
    final digestAttr = ASN1Sequence(elements: [
      oid(CraftOID.messageDigest),
      ASN1Set(elements: [
        ASN1OctetString(octets: DigestBytes.compute('SHA256', message))
      ])
    ]);
    if (!omitDigest) attrs.add(digestAttr);
    if (duplicateDigest) attrs.add(digestAttr);
    final attributes = ASN1Set(elements: attrs).encode();
    final signed = Signer('SHA-256/RSA')
      ..init(true, PrivateKeyParameter(private));
    final signature = signed.generateSignature(attributes).bytes;
    final signer = ASN1Sequence(elements: [
      ASN1Integer(BigInt.one),
      ASN1Sequence(elements: [
        ASN1Parser(certificate.getIssuerX500Name()).readSingle(),
        ASN1Integer(claimedSerial ?? serial)
      ]),
      algorithm(CraftOID.sha256),
      ASN1Object(0xa0, ASN1Utils.parse(attributes).content),
      algorithm(mechanism),
      ASN1OctetString(octets: signature),
    ]);
    final signedData = ASN1Sequence(elements: [
      ASN1Integer(BigInt.one),
      ASN1Set(elements: [algorithm(CraftOID.sha256)]),
      ASN1Sequence(elements: [
        oid(CraftOID.data),
        if (encapsulated)
          ASN1Sequence(tag: 0xa0, elements: [ASN1OctetString(octets: message)])
      ]),
      ASN1Sequence(
          tag: 0xa0,
          elements: [ASN1Parser(certificate.getEncoded()).readSingle()]),
      ASN1Set(elements: [signer]),
    ]);
    return ASN1Sequence(elements: [
      oid(CraftOID.signedData),
      ASN1Sequence(tag: 0xa0, elements: [signedData])
    ]).encode();
  }

  test('Valid detached CMS with 101-bit serial and zero padding verifies', () {
    final encoded = cms();
    final check = CraftPdfPKCS7.forVerifying(
        Uint8List.fromList([...encoded, 0, 0]), CraftPdfName.adbePkcs7Detached)
      ..update(message);
    expect(check.verify(), isTrue);
  });
  test(
      'CMS rejects mismatched mechanisms, identifiers and malformed signed attributes',
      () {
    for (final encoded in [
      cms(mechanism: '1.2.840.10045.4.3.2'),
      cms(mechanism: '1.2.840.113549.1.1.12'),
      cms(claimedSerial: serial + BigInt.one),
      cms(omitDigest: true),
      cms(duplicateDigest: true),
      cms(omitContentType: true),
      Uint8List.fromList([...cms(), 1]),
    ]) {
      final check =
          CraftPdfPKCS7.forVerifying(encoded, CraftPdfName.adbePkcs7Detached)
            ..update(message);
      expect(check.verify(), isFalse);
    }
  });
  test('Encapsulated CMS cannot authenticate an unrelated PDF', () {
    final check = CraftPdfPKCS7.forVerifying(
        cms(encapsulated: true), CraftPdfName.adbePkcs7Detached)
      ..update(Uint8List.fromList(ascii.encode('different document')));
    expect(check.verify(), isFalse);
  });
  test('Verification before completion does not consume prior updates', () {
    final check =
        CraftPdfPKCS7.forVerifying(cms(), CraftPdfName.adbePkcs7Detached);
    expect(check.verify(), isFalse);
    check.update(message, 0, 3);
    expect(check.verify(), isFalse);
    check.update(message, 3);
    expect(check.verify(), isTrue);
  });
  test('DER rejects nonminimal values, dirty unused bits and trailing data',
      () {
    for (final value in [
      [2, 2, 0, 1],
      [2, 0x81, 1, 1],
      [1, 1, 1],
      [3, 1, 1],
      [3, 2, 1, 1],
      [6, 2, 0x80, 1],
      [0x31, 6, 2, 1, 2, 2, 1, 1],
      [5, 0, 5, 0],
    ]) {
      expect(() => ASN1Parser(Uint8List.fromList(value)).readSingle(),
          throwsFormatException);
    }
  });
  test(
      'Certificate input is immutable; trailing data and inconsistent algorithms fail',
      () {
    final encoded = certificate.getEncoded();
    final cert = X509Certificate(encoded);
    encoded[0] = 0;
    cert.verify(cert.getPublicKey());
    final returned = cert.getEncoded();
    returned[0] = 0;
    expect(cert.getEncoded()[0], 0x30);
    expect(
        () => X509Certificate(
            Uint8List.fromList([...certificate.getEncoded(), 0])),
        throwsFormatException);
    final seq =
        ASN1Parser(certificate.getEncoded()).readSingle() as ASN1Sequence;
    seq.elements![1] = algorithm('1.2.840.113549.1.1.12');
    expect(() => X509Certificate(seq.encode()), throwsFormatException);
  });
  test('Invalid RSA parameters and AES zero-length offsets fail', () {
    expect(
        () => RSAPublicKey(BigInt.from(3233), BigInt.one), throwsArgumentError);
    expect(() => RSAPublicKey(BigInt.from(3232), BigInt.from(17)),
        throwsArgumentError);
    expect(() => RsaMath.randomBelow(BigInt.zero), throwsArgumentError);
    final cipher = CraftAESCipher(true, Uint8List(16), Uint8List(16));
    expect(() => cipher.processBlock(Uint8List(16), 17, 0), throwsRangeError);
    expect(() => cipher.processBlock(Uint8List(16), -1, 0), throwsRangeError);
  });
}
