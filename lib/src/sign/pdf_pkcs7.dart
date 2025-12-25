import 'dart:typed_data';

import '../kernel/pdf/pdf_name.dart';
import 'i_x509_certificate.dart';
import 'i_crypto_key.dart';
import 'i_external_digest.dart';
import 'oid.dart';
import 'digest_algorithms.dart';
import 'signature_mechanisms.dart';

/// This class does all the processing related to signing
/// and verifying a PKCS#7 / CMS signature.
///
/// TODO: This is a partial implementation - many methods need ASN.1 parsing
class PdfPKCS7 {
  // Signature info
  String? _signName;
  String? _reason;
  String? _location;
  DateTime? _signDate;

  // Version info
  int _version = 1;
  int _signerVersion = 1;

  // Algorithm info
  String? _digestAlgorithmOid;
  String? _signatureMechanismOid;

  // Certificate chain
  final List<IX509Certificate> _certs = [];
  IX509Certificate? _signCert;

  // Signature data
  Uint8List? _signatureValue;
  Uint8List? _digestAttr;
  Uint8List? _encapMessageContent;

  // Message digest
  IMessageDigest? _messageDigest;

  // Filter subtype
  PdfName? _filterSubtype;

  /// Whether this is a timestamp signature
  bool _isTsp = false;

  /// Whether this is a CAdES signature
  // ignore: unused_field
  bool _isCades = false;

  // External digest interface
  // ignore: unused_field
  IExternalDigest? _interfaceDigest;

  /// Creates a PdfPKCS7 for creating a new signature.
  ///
  /// @param privKey the private key (can be null for external signing)
  /// @param certChain the certificate chain
  /// @param hashAlgorithm the hash algorithm (e.g., "SHA-256")
  /// @param interfaceDigest the digest interface
  /// @param hasEncapContent true if using adbe.pkcs7.sha1 subfilter
  PdfPKCS7.forSigning(
    IPrivateKey? privKey,
    List<IX509Certificate> certChain,
    String hashAlgorithm,
    IExternalDigest interfaceDigest, {
    bool hasEncapContent = false,
  }) {
    _interfaceDigest = interfaceDigest;

    // Get digest algorithm OID
    _digestAlgorithmOid = DigestAlgorithms.getAllowedDigest(hashAlgorithm);
    if (_digestAlgorithmOid == null) {
      throw ArgumentError('Unknown hash algorithm: $hashAlgorithm');
    }

    // Copy certificates
    if (certChain.isNotEmpty) {
      _signCert = certChain.first;
      _certs.addAll(certChain);
    }

    // Find the signature algorithm
    if (privKey != null) {
      final signatureAlgo = privKey.getAlgorithm();
      final mechanismOid = SignatureMechanisms.getSignatureMechanismOid(
          signatureAlgo, hashAlgorithm);
      if (mechanismOid == null) {
        throw ArgumentError(
            'Could not determine signature mechanism OID for $signatureAlgo with $hashAlgorithm');
      }
      _signatureMechanismOid = mechanismOid;
    }

    // Initialize encapsulated content
    if (hasEncapContent) {
      _encapMessageContent = Uint8List(0);
      _messageDigest =
          DigestAlgorithms.getMessageDigest(getDigestAlgorithmName());
    }
  }

  /// Creates a PdfPKCS7 for verifying an existing signature.
  ///
  /// @param contentsKey the /Contents key from the signature dictionary
  /// @param filterSubtype the filter subtype (e.g., ETSI.CAdES.detached)
  PdfPKCS7.forVerifying(Uint8List contentsKey, PdfName filterSubtype) {
    _filterSubtype = filterSubtype;
    _isTsp = filterSubtype == PdfName.etsiRfc3161;
    _isCades = filterSubtype == PdfName.etsiCadesDetached;

    // TODO: Parse PKCS#7 SignedData structure
    // This requires ASN.1 parsing which is complex
    // For now, we'll just store the raw bytes
    _signatureValue = contentsKey;
  }

  /// Creates a PdfPKCS7 for RSA SHA1 signatures (adbe.x509.rsa_sha1).
  ///
  /// @param contentsKey the /Contents key
  /// @param certsKey the /Cert key
  PdfPKCS7.forRsaSha1(Uint8List contentsKey, Uint8List certsKey) {
    // TODO: Parse certificates from certsKey
    // TODO: Extract signature from contentsKey
    _signatureValue = contentsKey;
    _digestAlgorithmOid = '1.2.840.10040.4.3';
    _signatureMechanismOid = '1.3.36.3.3.1.2';
  }

  // Getters and setters

  /// Gets the signer name.
  String? getSignName() => _signName;

  /// Sets the signer name.
  void setSignName(String? signName) {
    _signName = signName;
  }

  /// Gets the signing reason.
  String? getReason() => _reason;

  /// Sets the signing reason.
  void setReason(String? reason) {
    _reason = reason;
  }

  /// Gets the signing location.
  String? getLocation() => _location;

  /// Sets the signing location.
  void setLocation(String? location) {
    _location = location;
  }

  /// Gets the sign date.
  DateTime? getSignDate() => _signDate;

  /// Sets the sign date.
  void setSignDate(DateTime signDate) {
    _signDate = signDate;
  }

  /// Gets the version of the PKCS#7 object.
  int getVersion() => _version;

  /// Gets the version of the PKCS#7 "SignerInfo" object.
  int getSigningInfoVersion() => _signerVersion;

  /// Gets the digest algorithm OID.
  String? getDigestAlgorithmOid() => _digestAlgorithmOid;

  /// Gets the digest algorithm name.
  String getDigestAlgorithmName() {
    if (_digestAlgorithmOid == null) {
      return 'SHA-256';
    }
    return DigestAlgorithms.getDigest(_digestAlgorithmOid!);
  }

  /// Gets the signature mechanism OID.
  String? getSignatureMechanismOid() => _signatureMechanismOid;

  /// Gets the signature mechanism name.
  String getSignatureMechanismName() {
    if (_signatureMechanismOid == null) {
      return 'SHA256withRSA';
    }

    switch (_signatureMechanismOid) {
      case OID.ed25519:
        return 'Ed25519';
      case OID.ed448:
        return 'Ed448';
      case OID.rsassaPss:
        return 'RSASSA-PSS';
      default:
        return SignatureMechanisms.getMechanism(
            _signatureMechanismOid!, getDigestAlgorithmName());
    }
  }

  /// Gets the signature algorithm name (disregarding digest).
  String getSignatureAlgorithmName() {
    if (_signatureMechanismOid == null) {
      return 'RSA';
    }
    return SignatureMechanisms.getAlgorithm(_signatureMechanismOid!);
  }

  /// Gets the filter subtype.
  PdfName? getFilterSubtype() => _filterSubtype;

  /// Gets the signing certificate.
  IX509Certificate? getSigningCertificate() => _signCert;

  /// Gets the certificate chain.
  List<IX509Certificate> getCertificates() => List.unmodifiable(_certs);

  /// Updates the digest with the specified bytes.
  void update(Uint8List buf, [int offset = 0, int? length]) {
    final len = length ?? (buf.length - offset);
    if (_encapMessageContent != null || _digestAttr != null || _isTsp) {
      _messageDigest?.update(buf, offset, len);
    }
    // TODO: Update signature object for verification
  }

  /// Sets the signature to an externally calculated value.
  void setExternalSignatureValue(
    Uint8List? signatureValue,
    Uint8List? signedMessageContent,
    String? signatureAlgorithm,
  ) {
    if (signatureValue != null) {
      _signatureValue = signatureValue;
    }
    if (signedMessageContent != null) {
      _encapMessageContent = signedMessageContent;
    }
    if (signatureAlgorithm != null) {
      final digestAlgo = getDigestAlgorithmName();
      final oid = SignatureMechanisms.getSignatureMechanismOid(
          signatureAlgorithm, digestAlgo);
      if (oid == null) {
        throw ArgumentError(
            'Could not determine signature mechanism OID for $signatureAlgorithm with $digestAlgo');
      }
      _signatureMechanismOid = oid;
    }
  }

  /// Gets the bytes for the PKCS#1 object.
  ///
  /// @return the encoded PKCS#1 bytes
  Uint8List getEncodedPKCS1() {
    if (_signatureValue == null) {
      throw StateError('No signature value available');
    }
    // TODO: Wrap in DER OCTET STRING
    return _signatureValue!;
  }

  /// Gets the bytes for the PKCS#7 SignedData object.
  ///
  /// @param secondDigest the digest in authenticated attributes
  /// @return the encoded PKCS#7 bytes
  Uint8List getEncodedPKCS7([Uint8List? secondDigest]) {
    // TODO: Build proper PKCS#7 SignedData structure
    // This requires significant ASN.1 encoding
    throw UnimplementedError('getEncodedPKCS7 not yet implemented');
  }

  /// Verifies the signature.
  ///
  /// @return true if the signature is valid
  bool verify() {
    // TODO: Implement signature verification
    throw UnimplementedError('verify not yet implemented');
  }

  /// Verifies the digest.
  ///
  /// @return true if the digest is valid
  bool verifyDigest() {
    // TODO: Implement digest verification
    throw UnimplementedError('verifyDigest not yet implemented');
  }
}
