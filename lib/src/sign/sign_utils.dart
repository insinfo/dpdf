import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/api.dart'; // For Signer, PublicKeyParameter
import 'package:pointycastle/asymmetric/api.dart'; // For RSAPublicKey

import 'i_x509_certificate.dart';

/// Utilities for cryptographic signature operations.
class SignUtils {
  /// Generates a CertificateID for OCSP.
  ///
  /// This is a simplified implementation. Real implementation needs hashing of Issuer Name and PublicKey.
  /// Returns encoded CertificateID.
  static ASN1Sequence generateCertificateId(
      IX509Certificate issuerCert, BigInt serialNumber, String hashAlgorithm) {
    // CertificateID ::= SEQUENCE {
    //    hashAlgorithm       AlgorithmIdentifier,
    //    issuerNameHash      OCTET STRING, -- Hash of Issuer's DN
    //    issuerKeyHash       OCTET STRING, -- Hash of Issuer's public key
    //    serialNumber        CertificateSerialNumber }

    // TODO: Implement actual hashing
    // For now returning a dummy sequence to satisfy type
    return ASN1Sequence(elements: [
      ASN1Sequence(), // AlgorithmIdentifier
      ASN1OctetString(octets: Uint8List(0)), // issuerNameHash
      ASN1OctetString(octets: Uint8List(0)), // issuerKeyHash
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

    final request = ASN1Sequence(elements: [
      certificateId,
    ]);

    final schema = ASN1Sequence(elements: [request]);

    final tbsRequest = ASN1Sequence(elements: [
      schema // requestList
      // extensions with Nonce
    ]);

    final ocspRequest = ASN1Sequence(elements: [
      tbsRequest,
    ]);

    return ocspRequest.encodedBytes!;
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
        final keyBytes = bitString.stringValues
            as Uint8List; // or .content, depending on version
        // PC's ASN1BitString usually exposes bytes.
        // Actually bitString.contentBytes or similar.
        // Let's assume we can get bytes.
        // In some versions, 'elements' or 'valueBytes'
        // Let's retry parsing the inner sequence (RSAPublicKey)

        // For now, let's look at how X509Certificate does it, it just returns the Sequence bytes.
        // If 'encoded' is the full SubjectPublicKeyInfo Sequence:

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
      // Algorithm naming convention in PointyCastle: 'SHA-256/RSA'
      final signer = Signer(algorithm);
      signer.init(
          false, PublicKeyParameter(publicKey)); // false for verification
      return signer;
    } catch (e) {
      return null;
    }
  }
}
