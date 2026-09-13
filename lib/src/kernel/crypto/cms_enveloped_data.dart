import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/aes_cipher.dart';
import 'package:dpdf/src/kernel/crypto/iv_generator.dart';
import 'package:dpdf/src/kernel/crypto/oid.dart';
import 'package:dpdf/src/kernel/crypto/rsa_key_transport.dart';
import 'package:dpdf/src/pki/rsa.dart';
import 'package:dpdf/src/pki/triple_des.dart';
import 'package:dpdf/src/sign/der_objects.dart';
import 'package:dpdf/src/sign/x509_certificate.dart';

/// Content encryption algorithms accepted inside the enveloped data of a
/// public-key security handler.
///
/// ISO 32000-1:2008, 7.6.4.3 lists "RC4 with key lengths up to 256-bits, DES,
/// Triple DES, RC2 with key lengths up to 128 bits, 128-bit AES in Cipher
/// Block Chaining (CBC) mode, 192-bit AES in CBC mode, 256-bit AES in CBC
/// mode". This implementation writes AES-CBC and additionally reads the
/// Triple DES variant produced by older writers.
enum CmsContentEncryption {
  aes128Cbc,
  aes192Cbc,
  aes256Cbc,
  desEde3Cbc,
}

/// One `KeyTransRecipientInfo` of RFC 2315 / RFC 5652.
class CmsRecipient {
  /// DER-encoded issuer `Name`.
  final Uint8List issuer;

  /// Certificate serial number.
  final BigInt serialNumber;

  /// The content encryption key wrapped with the recipient's public key.
  final Uint8List encryptedKey;

  CmsRecipient(
      {required this.issuer,
      required this.serialNumber,
      required this.encryptedKey});

  /// Whether [certificate] identifies this recipient.
  bool matches(X509Certificate certificate) {
    if (certificate.getSerialNumber() != serialNumber) return false;
    final other = certificate.getIssuerX500Name();
    if (other.length != issuer.length) return false;
    for (var i = 0; i < issuer.length; i++) {
      if (issuer[i] != other[i]) return false;
    }
    return true;
  }
}

/// A CMS/PKCS#7 `EnvelopedData` object as used by ISO 32000-1:2008, 7.6.4.3.
///
/// The enveloped data carries the 20-byte seed and, for the document-level
/// case, the four permission bytes. A content encryption key encrypts that
/// payload, and the key itself is wrapped once per recipient with the
/// recipient's RSA public key.
class CmsEnvelopedData {
  /// The recipients listed in the object, in encoding order.
  final List<CmsRecipient> recipients;

  /// The algorithm protecting the enveloped content.
  final CmsContentEncryption contentEncryption;

  /// The initialisation vector of the content encryption algorithm.
  final Uint8List initializationVector;

  /// The encrypted payload.
  final Uint8List encryptedContent;

  CmsEnvelopedData({
    required this.recipients,
    required this.contentEncryption,
    required this.initializationVector,
    required this.encryptedContent,
  });

  static const Map<CmsContentEncryption, String> _oids = {
    CmsContentEncryption.aes128Cbc: OID.aes128Cbc,
    CmsContentEncryption.aes192Cbc: OID.aes192Cbc,
    CmsContentEncryption.aes256Cbc: OID.aes256Cbc,
    CmsContentEncryption.desEde3Cbc: OID.desEde3Cbc,
  };

  /// The content encryption key length, in bytes.
  static int keyLengthOf(CmsContentEncryption algorithm) {
    switch (algorithm) {
      case CmsContentEncryption.aes128Cbc:
        return 16;
      case CmsContentEncryption.aes192Cbc:
        return 24;
      case CmsContentEncryption.aes256Cbc:
        return 32;
      case CmsContentEncryption.desEde3Cbc:
        return 24;
    }
  }

  /// Builds an enveloped data object protecting [content] for [certificates].
  ///
  /// Each recipient gets the same content encryption key, wrapped with its own
  /// RSA public key using RSAES-PKCS1-v1_5.
  static Uint8List encode({
    required List<X509Certificate> certificates,
    required Uint8List content,
    CmsContentEncryption algorithm = CmsContentEncryption.aes128Cbc,
    Uint8List? contentEncryptionKey,
    Uint8List? initializationVector,
  }) {
    if (certificates.isEmpty) {
      throw ArgumentError('An enveloped data object needs a recipient');
    }
    if (algorithm == CmsContentEncryption.desEde3Cbc) {
      throw UnsupportedError(
          'Triple DES enveloped data is supported for reading only');
    }
    final key =
        contentEncryptionKey ?? IVGenerator.getIVLen(keyLengthOf(algorithm));
    final iv = initializationVector ?? IVGenerator.getIV();
    final cipher = AESCipher(true, key, iv);
    final head = cipher.update(content, 0, content.length);
    final tail = cipher.doFinal();
    final encrypted = Uint8List(head.length + tail.length);
    encrypted.setRange(0, head.length, head);
    encrypted.setRange(head.length, encrypted.length, tail);

    final recipientInfos = ASN1Set(elements: [
      for (final certificate in certificates) _encodeRecipient(certificate, key)
    ]);

    final encryptedContentInfo = ASN1Sequence(elements: [
      ASN1ObjectIdentifier.fromIdentifierString(OID.pkcs7Data),
      ASN1Sequence(elements: [
        ASN1ObjectIdentifier.fromIdentifierString(_oids[algorithm]!),
        ASN1OctetString(octets: iv),
      ]),
      // [0] IMPLICIT OCTET STRING
      ASN1Object(0x80, encrypted),
    ]);

    final envelopedData = ASN1Sequence(elements: [
      ASN1Integer(BigInt.zero),
      recipientInfos,
      encryptedContentInfo,
    ]);

    return ASN1Sequence(elements: [
      ASN1ObjectIdentifier.fromIdentifierString(OID.pkcs7EnvelopedData),
      ASN1Sequence(elements: [envelopedData], tag: 0xA0),
    ]).encode();
  }

  static ASN1Sequence _encodeRecipient(
      X509Certificate certificate, Uint8List key) {
    final publicKey = RsaKeyTransport.publicKeyFromSubjectPublicKeyInfo(
        certificate.getPublicKey());
    return ASN1Sequence(elements: [
      ASN1Integer(BigInt.zero),
      ASN1Sequence(elements: [
        ASN1Parser(certificate.getIssuerX500Name()).readSingle(),
        ASN1Integer(certificate.getSerialNumber()),
      ]),
      ASN1Sequence(elements: [
        ASN1ObjectIdentifier.fromIdentifierString(OID.rsa),
        ASN1Null(),
      ]),
      ASN1OctetString(octets: RsaKeyTransport.encrypt(publicKey, key)),
    ]);
  }

  /// Parses a binary-encoded PKCS#7 enveloped data object.
  static CmsEnvelopedData decode(Uint8List encoded) {
    final contentInfo = ASN1Parser(encoded).readSingle();
    if (contentInfo is! ASN1Sequence || contentInfo.elements!.length < 2) {
      throw FormatException('Invalid PKCS#7 ContentInfo');
    }
    final contentType = contentInfo.elements![0];
    if (contentType is! ASN1ObjectIdentifier ||
        contentType.objectIdentifierAsString != OID.pkcs7EnvelopedData) {
      throw FormatException('The PKCS#7 object is not enveloped data');
    }
    final wrapper = contentInfo.elements![1];
    if (wrapper is! ASN1Sequence || wrapper.elements!.isEmpty) {
      throw FormatException('Invalid enveloped data wrapper');
    }
    final envelopedData = wrapper.elements![0];
    if (envelopedData is! ASN1Sequence || envelopedData.elements!.length < 3) {
      throw FormatException('Invalid EnvelopedData');
    }
    final recipientInfos = envelopedData.elements![1];
    if (recipientInfos is! ASN1Sequence) {
      throw FormatException('Invalid RecipientInfos');
    }
    final recipients = <CmsRecipient>[];
    for (final info in recipientInfos.elements!) {
      recipients.add(_decodeRecipient(info));
    }
    final encryptedContentInfo = envelopedData.elements![2];
    if (encryptedContentInfo is! ASN1Sequence ||
        encryptedContentInfo.elements!.length < 3) {
      throw FormatException('Invalid EncryptedContentInfo');
    }
    final algorithmIdentifier = encryptedContentInfo.elements![1];
    if (algorithmIdentifier is! ASN1Sequence ||
        algorithmIdentifier.elements!.length < 2) {
      throw FormatException('Invalid content encryption algorithm');
    }
    final algorithmOid = algorithmIdentifier.elements![0];
    if (algorithmOid is! ASN1ObjectIdentifier) {
      throw FormatException('Invalid content encryption algorithm identifier');
    }
    CmsContentEncryption? algorithm;
    for (final entry in _oids.entries) {
      if (entry.value == algorithmOid.objectIdentifierAsString) {
        algorithm = entry.key;
        break;
      }
    }
    if (algorithm == null) {
      throw UnsupportedError('Unsupported content encryption algorithm '
          '${algorithmOid.objectIdentifierAsString}');
    }
    final parameters = algorithmIdentifier.elements![1];
    if (parameters is! ASN1OctetString) {
      throw FormatException('Missing content encryption initialisation vector');
    }
    final content = encryptedContentInfo.elements![2];
    return CmsEnvelopedData(
      recipients: recipients,
      contentEncryption: algorithm,
      initializationVector: parameters.octets,
      encryptedContent: Uint8List.fromList(content.valueBytes),
    );
  }

  static CmsRecipient _decodeRecipient(ASN1Object info) {
    if (info is! ASN1Sequence || info.elements!.length < 4) {
      throw FormatException('Invalid KeyTransRecipientInfo');
    }
    final identifier = info.elements![1];
    if (identifier is! ASN1Sequence || identifier.elements!.length < 2) {
      throw UnsupportedError(
          'Only issuerAndSerialNumber recipients are supported');
    }
    final serial = identifier.elements![1];
    if (serial is! ASN1Integer) {
      throw FormatException('Invalid recipient serial number');
    }
    final encryptedKey = info.elements![3];
    if (encryptedKey is! ASN1OctetString) {
      throw FormatException('Invalid encrypted key');
    }
    return CmsRecipient(
      issuer: identifier.elements![0].encode(),
      serialNumber: serial.integer!,
      encryptedKey: encryptedKey.octets,
    );
  }

  /// Recovers the enveloped payload with the private key of [certificate].
  ///
  /// Returns `null` when the certificate does not appear in the recipient
  /// list, so callers can try the next certificate they hold.
  Uint8List? unwrap(X509Certificate certificate, RSAPrivateKey privateKey) {
    for (final recipient in recipients) {
      if (!recipient.matches(certificate)) continue;
      final key = RsaKeyTransport.decrypt(privateKey, recipient.encryptedKey);
      return _decryptContent(key);
    }
    return null;
  }

  /// Recovers the enveloped payload with an already unwrapped content key.
  Uint8List decryptContentWithKey(Uint8List key) => _decryptContent(key);

  Uint8List _decryptContent(Uint8List key) {
    if (contentEncryption == CmsContentEncryption.desEde3Cbc) {
      return TripleDes.decryptCbc(encryptedContent,
          key: key, iv: initializationVector);
    }
    if (key.length != keyLengthOf(contentEncryption)) {
      throw FormatException('Unwrapped content encryption key has the '
          'wrong length for the declared algorithm');
    }
    final cipher = AESCipher(false, key, initializationVector);
    final head = cipher.update(encryptedContent, 0, encryptedContent.length);
    final tail = cipher.doFinal();
    final result = Uint8List(head.length + tail.length);
    result.setRange(0, head.length, head);
    result.setRange(head.length, result.length, tail);
    return result;
  }
}
