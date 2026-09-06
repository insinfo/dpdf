import 'dart:typed_data';

import '../kernel/pdf/pdf_name.dart';
import 'i_crypto_key.dart';
import 'i_external_digest.dart';
import 'i_tsa_client.dart';

import 'oid.dart';
import 'digest_algorithms.dart';
import 'signature_mechanisms.dart';
import 'package:pointycastle/asymmetric/api.dart'; // For RSASignature

import 'sign_utils.dart';
import 'x509_certificate.dart';
import 'i_x509_certificate.dart';
import 'asn1_utils.dart';

/// This class does all the processing related to signing
/// and verifying a PKCS#7 / CMS signature.
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
  final List<Uint8List> _certsDer = []; // DER-encoded certificates

  // Signature data
  Uint8List? _signatureValue;
  Uint8List? _digestAttr;
  // ignore: unused_field
  Uint8List? _sigAttr; // Signed attributes (DER)
  Uint8List? _encapMessageContent;
  // ignore: unused_field
  Uint8List? _rawSignedData; // Raw PKCS#7 data

  // Message digest
  IMessageDigest? _messageDigest;

  // Filter subtype
  PdfName? _filterSubtype;

  /// Whether this is a timestamp signature
  bool _isTsp = false;

  /// Whether this is a CAdES signature
  bool _isCades = false;

  // External digest interface
  // ignore: unused_field
  IExternalDigest? _interfaceDigest;

  // Signer identification
  Uint8List? _signerIssuer; // DER encoded Issuer DN
  BigInt? _signerSerialNumber;
  Uint8List? _signerSubjectKeyIdentifier;
  IX509Certificate? _signCert;

  // Verify result
  bool? _verifyResult;

  /// Creates a PdfPKCS7 for creating a new signature.
  ///
  /// @param privKey the private key (can be null for external signing)
  /// @param certChain the certificate chain (DER-encoded)
  /// @param hashAlgorithm the hash algorithm (e.g., "SHA-256")
  /// @param interfaceDigest the digest interface
  /// @param hasEncapContent true if using adbe.pkcs7.sha1 subfilter
  PdfPKCS7.forSigning(
    IPrivateKey? privKey,
    List<Uint8List> certChain,
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
    _certsDer.addAll(certChain);

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

    // Link the private key to the signing certificate (assumed first in chain)
    if (_certsDer.isNotEmpty) {
      _signCert = X509Certificate(_certsDer[0]);
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
    _rawSignedData = contentsKey;

    // Parse PKCS#7 SignedData structure
    _parseSignedData(contentsKey);
  }

  /// Creates a PdfPKCS7 for RSA SHA1 signatures (adbe.x509.rsa_sha1).
  ///
  /// @param contentsKey the /Contents key
  /// @param certsKey the /Cert key (DER-encoded certificates)
  PdfPKCS7.forRsaSha1(Uint8List contentsKey, Uint8List certsKey) {
    _signatureValue = contentsKey;
    _digestAlgorithmOid = OID.sha1;
    _signatureMechanismOid = OID.rsaSha1;

    // Parse certificates from certsKey
    _parseCertificates(certsKey);
  }

  /// Parses PKCS#7 SignedData structure.
  void _parseSignedData(Uint8List data) {
    try {
      // ContentInfo ::= SEQUENCE {
      //   contentType ContentType,
      //   content [0] EXPLICIT ANY DEFINED BY contentType }
      final contentInfo = ASN1Utils.parse(data);
      if (!contentInfo.isSequence) {
        throw FormatException('Expected SEQUENCE for ContentInfo');
      }

      final contentInfoElements = ASN1Utils.parseElements(contentInfo.content);
      if (contentInfoElements.length < 2) {
        throw FormatException('ContentInfo must have at least 2 elements');
      }

      // Check contentType is signedData
      final contentTypeOid = _parseOID(contentInfoElements[0].content);
      if (contentTypeOid != OID.signedData) {
        throw FormatException('Expected signedData OID, got: $contentTypeOid');
      }

      // Get the SignedData content (tagged [0])
      if (!contentInfoElements[1].isContextSpecific) {
        throw FormatException('Expected context-specific tag for content');
      }

      final signedDataSeq = ASN1Utils.parse(contentInfoElements[1].content);
      if (!signedDataSeq.isSequence) {
        throw FormatException('Expected SEQUENCE for SignedData');
      }

      final signedDataElements = ASN1Utils.parseElements(signedDataSeq.content);

      // SignedData ::= SEQUENCE {
      //   version CMSVersion,
      //   digestAlgorithms DigestAlgorithmIdentifiers,
      //   encapContentInfo EncapsulatedContentInfo,
      //   certificates [0] IMPLICIT CertificateSet OPTIONAL,
      //   crls [1] IMPLICIT RevocationInfoChoices OPTIONAL,
      //   signerInfos SignerInfos }

      int idx = 0;

      // Version
      if (signedDataElements[idx].isInteger) {
        _version = _parseInteger(signedDataElements[idx].content);
        idx++;
      }

      // DigestAlgorithms (SET)
      if (idx < signedDataElements.length && signedDataElements[idx].isSet) {
        final digestAlgos =
            ASN1Utils.parseElements(signedDataElements[idx].content);
        if (digestAlgos.isNotEmpty) {
          final algoId = ASN1Utils.parseElements(digestAlgos[0].content);
          if (algoId.isNotEmpty && algoId[0].isOid) {
            _digestAlgorithmOid = _parseOID(algoId[0].content);
          }
        }
        idx++;
      }

      // EncapsulatedContentInfo
      if (idx < signedDataElements.length &&
          signedDataElements[idx].isSequence) {
        final encapContent =
            ASN1Utils.parseElements(signedDataElements[idx].content);
        // Check if there's actual content (tag [0])
        if (encapContent.length > 1 && encapContent[1].isContextSpecific) {
          final contentOctet = ASN1Utils.parse(encapContent[1].content);
          if (contentOctet.isOctetString) {
            _encapMessageContent = contentOctet.content;
          }
        }
        idx++;
      }

      // Parse optional certificates [0] and crls [1]
      while (idx < signedDataElements.length &&
          signedDataElements[idx].isContextSpecific) {
        final tagNum = signedDataElements[idx].tagNumber;
        if (tagNum == 0) {
          // Certificates
          _parseCertificateSet(signedDataElements[idx].content);
        }
        // Skip crls [1]
        idx++;
      }

      // SignerInfos (SET)
      if (idx < signedDataElements.length && signedDataElements[idx].isSet) {
        final signerInfos =
            ASN1Utils.parseElements(signedDataElements[idx].content);
        if (signerInfos.isNotEmpty) {
          _parseSignerInfo(signerInfos[0]);
        }
      }

      // Initialize message digest if we have encapsulated content or signed attributes
      if (_encapMessageContent != null || _digestAttr != null) {
        _messageDigest =
            DigestAlgorithms.getMessageDigest(getDigestAlgorithmName());
      }
    } catch (e) {
      // If parsing fails, just store the signature value for basic verification
      _signatureValue = data;
    }
  }

  /// Parses a SignerInfo structure.
  void _parseSignerInfo(ASN1ParseResult signerInfo) {
    if (!signerInfo.isSequence) return;

    final elements = ASN1Utils.parseElements(signerInfo.content);
    int idx = 0;

    // Version
    if (idx < elements.length && elements[idx].isInteger) {
      _signerVersion = _parseInteger(elements[idx].content);
      idx++;
    }

    // SignerIdentifier (IssuerAndSerialNumber or SubjectKeyIdentifier)
    if (idx < elements.length) {
      final sid = elements[idx];
      if (sid.isSequence) {
        // IssuerAndSerialNumber
        final sidElements = ASN1Utils.parseElements(sid.content);
        if (sidElements.length > 1) {
          _signerIssuer = sidElements[0]
              .encodedBytes; // Use encoded bytes for comparison or Store element
          _signerSerialNumber =
              BigInt.from(_parseInteger(sidElements[1].content));
        }
      } else if (sid.isContextSpecific && sid.tagNumber == 0) {
        // SubjectKeyIdentifier [0] IMPLICIT OCTET STRING
        _signerSubjectKeyIdentifier = sid.content;
      }
      idx++;
    }

    // DigestAlgorithmIdentifier
    if (idx < elements.length && elements[idx].isSequence) {
      final algoId = ASN1Utils.parseElements(elements[idx].content);
      if (algoId.isNotEmpty && algoId[0].isOid) {
        _digestAlgorithmOid = _parseOID(algoId[0].content);
      }
      idx++;
    }

    // SignedAttributes [0] IMPLICIT
    if (idx < elements.length &&
        elements[idx].isContextSpecific &&
        elements[idx].tagNumber == 0) {
      _sigAttr = Uint8List.fromList(
          [0x31, ...elements[idx].content]); // Re-encode as SET
      _parseSignedAttributes(elements[idx].content);
      idx++;
    }

    // SignatureAlgorithmIdentifier
    if (idx < elements.length && elements[idx].isSequence) {
      final algoId = ASN1Utils.parseElements(elements[idx].content);
      if (algoId.isNotEmpty && algoId[0].isOid) {
        _signatureMechanismOid = _parseOID(algoId[0].content);
      }
      idx++;
    }

    // SignatureValue
    if (idx < elements.length && elements[idx].isOctetString) {
      _signatureValue = elements[idx].content;
      idx++;
    }
  }

  /// Parses signed attributes.
  void _parseSignedAttributes(Uint8List content) {
    try {
      final attrs = ASN1Utils.parseElements(content);
      for (final attr in attrs) {
        if (!attr.isSequence) continue;

        final attrElements = ASN1Utils.parseElements(attr.content);
        if (attrElements.length < 2) continue;

        if (!attrElements[0].isOid) continue;
        final attrOid = _parseOID(attrElements[0].content);

        // Message digest attribute
        if (attrOid == OID.messageDigest) {
          final values = ASN1Utils.parseElements(attrElements[1].content);
          if (values.isNotEmpty && values[0].isOctetString) {
            _digestAttr = values[0].content;
          }
        }
      }
    } catch (e) {
      // Ignore parsing errors in attributes
    }
  }

  /// Parses a certificate set.
  void _parseCertificateSet(Uint8List content) {
    try {
      int offset = 0;
      while (offset < content.length) {
        // Parse each certificate
        final cert = ASN1Utils.parse(content, offset);
        if (cert.isSequence) {
          // Re-encode as DER
          final certDer = content.sublist(offset, offset + cert.totalLength);
          _certsDer.add(certDer);
        }
        offset += cert.totalLength;
        if (cert.totalLength == 0) break;
      }
    } catch (e) {
      // Ignore parsing errors
    }
  }

  /// Parses certificates from a blob.
  void _parseCertificates(Uint8List data) {
    _parseCertificateSet(data);
  }

  /// Parses an OID from ASN.1 content.
  String _parseOID(Uint8List content) {
    if (content.isEmpty) return '';

    final result = StringBuffer();

    // First byte encodes first two components
    result.write(content[0] ~/ 40);
    result.write('.');
    result.write(content[0] % 40);

    // Decode remaining components using base-128
    int value = 0;
    for (int i = 1; i < content.length; i++) {
      value = (value << 7) | (content[i] & 0x7F);
      if ((content[i] & 0x80) == 0) {
        result.write('.');
        result.write(value);
        value = 0;
      }
    }

    return result.toString();
  }

  /// Parses an integer from ASN.1 content.
  int _parseInteger(Uint8List content) {
    if (content.isEmpty) return 0;

    int value = 0;
    bool isNegative = (content[0] & 0x80) != 0;

    for (int i = 0; i < content.length; i++) {
      value = (value << 8) | content[i];
    }

    if (isNegative) {
      // Two's complement
      value = value - (1 << (content.length * 8));
    }

    return value;
  }

  /// Verifies that signature integrity is intact and authentic.
  bool verify() {
    if (_verifyResult != null) return _verifyResult!;

    try {
      if (_signatureValue == null) return false;

      // 1. Find Signing Certificate
      _findSigningCertificate();
      if (_signCert == null) {
        return false;
      }

      // 2. Prepare message digest
      if (_messageDigest == null) {
        _messageDigest =
            DigestAlgorithms.getMessageDigest(getDigestAlgorithmName());
      }

      // 3. Verify digest is consistent (integrity)
      if (_sigAttr != null) {
        if (_digestAttr == null) return false;

        // Check if content hash matches digest attribute
        if (_encapMessageContent != null) {
          _messageDigest!.reset();
          _messageDigest!.update(_encapMessageContent!);
          final hash = _messageDigest!.digest();
          if (!_arraysEqual(hash, _digestAttr!)) {
            return false;
          }
        }
      } else {
        // Signature verification over _encapMessageContent
        if (_encapMessageContent != null) {
          _messageDigest!.update(_encapMessageContent!);
        }
      }

      // 4. Verify Signature (Authenticity)
      final publicKeyInfo = _signCert!.getPublicKey();
      final publicKey =
          SignUtils.parsePublicKeyFromSubjectPublicKeyInfo(publicKeyInfo);

      if (publicKey == null) {
        return false;
      }

      final signer = SignUtils.createSigner(
          '${getDigestAlgorithmName()}withRSA', publicKey);

      if (signer == null) {
        return false;
      }

      final sig = RSASignature(_signatureValue!);

      if (_sigAttr != null) {
        _verifyResult = signer.verifySignature(_sigAttr!, sig);
      } else if (_encapMessageContent != null) {
        _verifyResult = signer.verifySignature(_encapMessageContent!, sig);
      } else {
        _verifyResult = false;
      }

      return _verifyResult!;
    } catch (e) {
      return false;
    }
  }

  void _findSigningCertificate() {
    if (_signCert != null) return;

    if (_signerIssuer != null && _signerSerialNumber != null) {
      for (final certDer in _certsDer) {
        final cert = X509Certificate(certDer);
        // TODO: proper DN comparison (normalization)
        // For now, simple string comparison might fail if encoding differs
        // But we can compare Serial Number at least
        if (cert.getSerialNumber() == _signerSerialNumber) {
          final certIssuer = cert.getIssuerX500Name();
          if (_arraysEqual(certIssuer, _signerIssuer!)) {
            _signCert = cert;
            return;
          }
        }
      }
    } else if (_signerSubjectKeyIdentifier != null) {
      for (final certDer in _certsDer) {
        final cert = X509Certificate(certDer);
        final ski = cert.getSubjectKeyIdentifier();
        if (ski != null && _arraysEqual(ski, _signerSubjectKeyIdentifier!)) {
          _signCert = cert;
          return;
        }
      }
    }
    // Fallback: if only 1 cert, assume it is the signer
    if (_certsDer.length == 1) {
      _signCert = X509Certificate(_certsDer[0]);
    }
  }

  bool _arraysEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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

  /// Gets the DER-encoded certificates.
  List<Uint8List> getCertificatesDer() => List.unmodifiable(_certsDer);

  /// Gets the digest attribute (message digest from signed attributes).
  Uint8List? getDigestAttr() => _digestAttr;

  /// Gets the encapsulated content.
  Uint8List? getEncapMessageContent() => _encapMessageContent;

  /// Gets whether this is a timestamp signature.
  bool isTsp() => _isTsp;

  /// Gets whether this is a CAdES signature.
  bool isCades() => _isCades;

  /// Updates the digest with the specified bytes.
  void update(Uint8List buf, [int offset = 0, int? length]) {
    final len = length ?? (buf.length - offset);
    if (_encapMessageContent != null || _digestAttr != null || _isTsp) {
      _messageDigest?.update(buf, offset, len);
    }
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

  /// Gets the raw signature value.
  Uint8List? getSignatureValue() => _signatureValue;

  /// Gets the bytes for the PKCS#1 object.
  ///
  /// @return the encoded PKCS#1 bytes
  Uint8List getEncodedPKCS1() {
    if (_signatureValue == null) {
      throw StateError('No signature value available');
    }
    // Wrap in DER OCTET STRING
    return ASN1Utils.createOctetString(_signatureValue!);
  }

  /// Builds the authenticated attributes for signing.
  ///
  /// @param secondDigest the message digest
  /// @return the DER-encoded authenticated attributes
  Uint8List buildAuthenticatedAttributes(Uint8List secondDigest) {
    final attrs = <Uint8List>[];

    // Content type attribute
    attrs.add(ASN1Utils.createSequence([
      ASN1Utils.createOID(OID.contentType),
      ASN1Utils.createSet([
        ASN1Utils.createOID(OID.data),
      ]),
    ]));

    // Signing time attribute
    if (_signDate != null) {
      attrs.add(ASN1Utils.createSequence([
        ASN1Utils.createOID(OID.signingTime),
        ASN1Utils.createSet([
          ASN1Utils.createUtcTime(_signDate!),
        ]),
      ]));
    }

    // Message digest attribute
    attrs.add(ASN1Utils.createSequence([
      ASN1Utils.createOID(OID.messageDigest),
      ASN1Utils.createSet([
        ASN1Utils.createOctetString(secondDigest),
      ]),
    ]));

    return ASN1Utils.createSet(attrs);
  }

  /// Gets the encoded PKCS#7 object.
  Future<Uint8List> getEncodedPKCS7(
    Uint8List secondDigest, {
    ITSAClient? tsaClient,
    List<Uint8List>? ocsp,
    List<Uint8List>? crlBytes,
  }) async {
    if (_signatureMechanismOid == null || _digestAlgorithmOid == null) {
      throw StateError('Signature mechanism or digest algorithm not set');
    }

    final signedDataElements = <Uint8List>[];

    // Version
    signedDataElements.add(ASN1Utils.createIntegerFromInt(1));

    // DigestAlgorithmIdentifiers
    signedDataElements.add(ASN1Utils.createSet([
      ASN1Utils.createSequence(
          [ASN1Utils.createOID(_digestAlgorithmOid!), ASN1Utils.createNull()])
    ]));

    // EncapsulatedContentInfo
    final encapContent = <Uint8List>[];
    encapContent.add(ASN1Utils.createOID(OID.data));
    if (_encapMessageContent != null) {
      // [0] EXPLICIT OCTET STRING
      encapContent.add(ASN1Utils.encodeTagged(
          0xA0, ASN1Utils.createOctetString(_encapMessageContent!)));
    }
    signedDataElements.add(ASN1Utils.createSequence(encapContent));

    // Certificates [0] IMPLICIT SET
    if (_certsDer.isNotEmpty) {
      final certs = <Uint8List>[];
      for (var c in _certsDer) certs.add(c);
      final setOfCerts = ASN1Utils.createSet(certs);
      // Change 0x31 (SET) to 0xA0 ([0] IMPLICIT)
      final implicitCerts = Uint8List.fromList(setOfCerts);
      implicitCerts[0] = 0xA0;
      signedDataElements.add(implicitCerts);
    }

    // CRLs [1] IMPLICIT SET
    if ((crlBytes != null && crlBytes.isNotEmpty) ||
        (ocsp != null && ocsp.isNotEmpty)) {
      final revs = <Uint8List>[];
      if (crlBytes != null) {
        for (var c in crlBytes) revs.add(c);
      }
      if (ocsp != null) {
        for (var o in ocsp) {
          // OCSP Response is added as OtherRevocationInfoFormat
          final other = <Uint8List>[];
          other.add(ASN1Utils.createOID(OID.ocspResponse));
          // Wrap in EXPLICIT tag if needed or just add as is?
          // RFC 5652: otherRevInfo ANY DEFINED BY otherRevInfoFormat
          other.add(o);
          final seq = ASN1Utils.createSequence(other);
          // RevocationInfoChoice CHOICE { ..., other [1] IMPLICIT OtherRevocationInfoFormat }
          final tagged = Uint8List.fromList(seq);
          tagged[0] = 0xA1;
          revs.add(tagged);
        }
      }
      final setOfRevs = ASN1Utils.createSet(revs);
      final implicitRevs = Uint8List.fromList(setOfRevs);
      implicitRevs[0] = 0xA1;
      signedDataElements.add(implicitRevs);
    }

    // SignerInfos
    final signerInfo = await _buildSignerInfo(secondDigest, tsaClient);
    signedDataElements.add(ASN1Utils.createSet([signerInfo]));

    final content = ASN1Utils.createSequence(signedDataElements);

    // ContentInfo: SEQUENCE { OID signedData, [0] EXPLICIT content }
    final elements = <Uint8List>[];
    elements.add(ASN1Utils.createOID(OID.signedData));
    elements.add(ASN1Utils.encodeTagged(0xA0, content));

    return ASN1Utils.createSequence(elements);
  }

  /// Builds the SignerInfo structure.
  Future<Uint8List> _buildSignerInfo(
      Uint8List secondDigest, ITSAClient? tsaClient) async {
    final elements = <Uint8List>[];

    // Version
    elements.add(ASN1Utils.createIntegerFromInt(1));

    // SignerIdentifier (IssuerAndSerialNumber)
    if (_signCert != null) {
      final issuer = _signCert!.getIssuerX500Name();
      final serial = _signCert!.getSerialNumber();
      elements.add(
          ASN1Utils.createSequence([issuer, ASN1Utils.createInteger(serial)]));
    } else {
      throw StateError("Signing certificate not set");
    }

    // DigestAlgorithmIdentifier
    elements.add(ASN1Utils.createSequence([
      ASN1Utils.createOID(_digestAlgorithmOid!),
      ASN1Utils.createNull(),
    ]));

    // SignedAttributes [0] IMPLICIT
    final authAttrs = buildAuthenticatedAttributes(secondDigest);
    // The authAttrs returned is a SET (tag 0x31).
    // We want [0] IMPLICIT SET -> Tag 0xA0.
    final implicitAttrs = Uint8List.fromList(authAttrs);
    implicitAttrs[0] = 0xA0;
    elements.add(implicitAttrs);

    // SignatureAlgorithmIdentifier
    elements.add(ASN1Utils.createSequence([
      ASN1Utils.createOID(_signatureMechanismOid ?? OID.rsaSha256),
      ASN1Utils.createNull(),
    ]));

    // SignatureValue
    elements.add(ASN1Utils.createOctetString(_signatureValue!));

    // UnsignedAttributes [1] IMPLICIT
    if (tsaClient != null) {
      final tsaToken = await tsaClient.getTimeStampToken(_signatureValue!);

      final attrContent = <Uint8List>[];
      attrContent.add(ASN1Utils.createOID(OID.signatureTimeStampToken));
      attrContent.add(ASN1Utils.createSet([tsaToken]));

      final attr = ASN1Utils.createSequence(attrContent);

      // UnsignedAttrs is [1] IMPLICIT SET OF Attribute
      // Tag 0xA1 (Context 1 Constructed)
      final setOfAttrs = ASN1Utils.createSet([attr]);
      final implicitUnsigned = Uint8List.fromList(setOfAttrs);
      implicitUnsigned[0] = 0xA1;

      elements.add(implicitUnsigned);
    }

    return ASN1Utils.createSequence(elements);
  }

  /// Verifies the message digest.
  ///
  /// @return true if the digest matches
  bool verifyDigest() {
    if (_digestAttr == null || _messageDigest == null) {
      return false;
    }

    final calculatedDigest = _messageDigest!.digest();

    if (calculatedDigest.length != _digestAttr!.length) {
      return false;
    }

    for (int i = 0; i < calculatedDigest.length; i++) {
      if (calculatedDigest[i] != _digestAttr![i]) {
        return false;
      }
    }

    return true;
  }
}
