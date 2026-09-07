import 'dart:typed_data';

import 'package:dpdf/src/sign/der_objects.dart';
import 'package:dpdf/src/pki/rsa.dart';

import 'certificate_details.dart';
import '../commons/digest/digest_bytes.dart';

/// Utilities for cryptographic signature operations.
class CraftSignUtils {
  /// Generates a CertificateID for OCSP.
  ///
  /// This is a simplified implementation. Real implementation needs hashing of Issuer Name and PublicKey.
  /// Returns encoded CertificateID.
  static ASN1Sequence generateCertificateId(CertificateDetails issuerCert,
      BigInt serialNumber, String hashAlgorithm) {
    // CertificateID ::= SEQUENCE {
    //    hashAlgorithm       AlgorithmIdentifier,
    //    issuerNameHash      OCTET STRING, -- Hash of Issuer's DN
    //    issuerKeyHash       OCTET STRING, -- Hash of Issuer's public key
    //    serialNumber        CertificateSerialNumber }

    const oids = {
      'SHA1': '1.3.14.3.2.26',
      'SHA256': '2.16.840.1.101.3.4.2.1',
      'SHA384': '2.16.840.1.101.3.4.2.2',
      'SHA512': '2.16.840.1.101.3.4.2.3'
    };
    final oid = oids[hashAlgorithm.toUpperCase().replaceAll('-', '')];
    if (oid == null) {
      throw UnsupportedError('Unsupported OCSP hash $hashAlgorithm');
    }
    final spki =
        ASN1Parser(issuerCert.getPublicKey()).nextObject() as ASN1Sequence;
    final publicBits = spki.elements![1] as ASN1BitString;
    final certificate =
        ASN1Parser(issuerCert.getEncoded()).nextObject() as ASN1Sequence;
    final tbs = certificate.elements!.first as ASN1Sequence;
    final start = tbs.elements!.first.tag == 0xa0 ? 1 : 0;
    final subject = tbs.elements![start + 4].encode();
    return ASN1Sequence(elements: [
      ASN1Sequence(elements: [
        ASN1ObjectIdentifier.fromIdentifierString(oid),
        ASN1Null()
      ]),
      ASN1OctetString(octets: DigestBytes.compute(hashAlgorithm, subject)),
      ASN1OctetString(
          octets: DigestBytes.compute(hashAlgorithm, publicBits.stringValues)),
      ASN1Integer(serialNumber),
    ]);
  }

  /// Generates an OCSP Request with Nonce.
  static Uint8List generateOcspRequestWithNonce(ASN1Sequence certificateId) {
    // OCSPRequest ::= SEQUENCE {
    //     tbsRequest      TBSRequest,
    //     optionalSignature   [0]     EXPLICIT Signature OPTIONAL }

    // TBSRequest ::= SEQUENCE {
    //     version             [0]     EXPLICIT Version DEFAULT v1,
    //     requestorName       [1]     EXPLICIT GeneralName OPTIONAL,
    //     requestList                 SEQUENCE OF Request,
    //     requestExtensions   [2]     EXPLICIT Extensions OPTIONAL }

    // Request ::= SEQUENCE {
    //     reqCert                     CertID,
    //     singleRequestExtensions     [0] EXPLICIT Extensions OPTIONAL }

    final nonce = RsaMath.randomBytes(16);
    final extension = ASN1Sequence(elements: [
      ASN1ObjectIdentifier.fromIdentifierString('1.3.6.1.5.5.7.48.1.2'),
      ASN1OctetString(octets: ASN1OctetString(octets: nonce).encode()),
    ]);
    final tbsRequest = ASN1Sequence(elements: [
      ASN1Sequence(elements: [
        ASN1Sequence(elements: [certificateId])
      ]),
      ASN1Sequence(tag: 0xa2, elements: [
        ASN1Sequence(elements: [extension])
      ]),
    ]);
    return ASN1Sequence(elements: [tbsRequest]).encode();
  }

  /// Parses an RSA Public Key from SubjectPublicKeyInfo bytes.
  static RSAPublicKey? parsePublicKeyFromSubjectPublicKeyInfo(
      Uint8List encoded) {
    try {
      final parser = ASN1Parser(encoded);
      final seq = parser.nextObject() as ASN1Sequence;

      if (seq.elements!.length < 2) return null;

      // skip AlgorithmIdentifier (elements[0])

      final bitString = seq.elements![1];
      if (bitString is ASN1BitString) {
        final keyBytes = bitString.stringValues;
        final rsaParser = ASN1Parser(keyBytes);
        final rsaSeq = rsaParser.nextObject() as ASN1Sequence;
        if (rsaSeq.elements!.length < 2) return null;

        final modulus = rsaSeq.elements![0] as ASN1Integer;
        final exponent = rsaSeq.elements![1] as ASN1Integer;

        return RSAPublicKey(modulus.integer!, exponent.integer!);
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  /// Creates a signer for the given algorithm name and public key.
  static Signer? createSigner(String algorithm, RSAPublicKey publicKey) {
    try {
      // Digest and RSA scheme are resolved by the local signer.
      final normalized = algorithm.replaceFirst(
          RegExp(r'withRSA$', caseSensitive: false), '/RSA');
      final signer = Signer(normalized);
      signer.init(
          false, PublicKeyParameter(publicKey)); // false for verification
      return signer;
    } catch (e) {
      return null;
    }
  }
}
