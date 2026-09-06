import 'dart:typed_data';

import '../kernel/pdf/pdf_name.dart';
import 'signing_key.dart';
import 'external_digest.dart';
import 'tsa_client.dart';

import 'oid.dart';
import 'digest_algorithms.dart';
import 'signature_mechanisms.dart';
import 'package:pdfcraft/src/pki/rsa.dart';

import 'sign_utils.dart';
import 'x509_certificate.dart';
import 'certificate_details.dart';
import 'asn1_utils.dart';
import 'der_objects.dart';

/// This class does all the processing related to signing
/// and verifying a PKCS#7 / CMS signature.
class CraftPdfPKCS7 {
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
  SigningDigest? _messageDigest;

  // Filter subtype
  CraftPdfName? _filterSubtype;

  /// Whether this is a timestamp signature
  bool _isTsp = false;

  /// Whether this is a CAdES signature
  bool _isCades = false;

  // External digest interface
  // ignore: unused_field
  CraftExternalDigest? _interfaceDigest;

  // Signer identification
  Uint8List? _signerIssuer; // DER encoded Issuer DN
  BigInt? _signerSerialNumber;
  Uint8List? _signerSubjectKeyIdentifier;
  CertificateDetails? _signCert;

  // Verify result
  bool? _verifyResult;
  Uint8List? _calculatedContentDigest;
  bool _receivedContent = false;
  bool _parseFailed = false;
  String? _encapContentType;
  final BytesBuilder _verificationContent = BytesBuilder();

  /// Creates a PdfPKCS7 for creating a new signature.
  ///
  /// @param privKey the private key (can be null for external signing)
  /// @param certChain the certificate chain (DER-encoded)
  /// @param hashAlgorithm the hash algorithm (e.g., "SHA-256")
  /// @param interfaceDigest the digest interface
  /// @param hasEncapContent true if using adbe.pkcs7.sha1 subfilter
  CraftPdfPKCS7.forSigning(
    SigningPrivateKey? privKey,
    List<Uint8List> certChain,
    String hashAlgorithm,
    CraftExternalDigest interfaceDigest, {
    bool hasEncapContent = false,
  }) {
    _interfaceDigest = interfaceDigest;

    // Get digest algorithm OID
    _digestAlgorithmOid = CraftDigestAlgorithms.getAllowedDigest(hashAlgorithm);
    if (_digestAlgorithmOid == null) {
      throw ArgumentError('Unknown hash algorithm: $hashAlgorithm');
    }

    // Copy certificates
    _certsDer.addAll(certChain);

    // Find the signature algorithm
    if (privKey != null) {
      final signatureAlgo = privKey.getAlgorithm();
      final mechanismOid = CraftSignatureMechanisms.getSignatureMechanismOid(
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
          CraftDigestAlgorithms.getMessageDigest(getDigestAlgorithmName());
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
  CraftPdfPKCS7.forVerifying(
      Uint8List contentsKey, CraftPdfName filterSubtype) {
    _filterSubtype = filterSubtype;
    _isTsp = filterSubtype == CraftPdfName.etsiRfc3161;
    _isCades = filterSubtype == CraftPdfName.etsiCadesDetached;
    _rawSignedData = contentsKey;

    // Parse PKCS#7 SignedData structure
    _parseSignedData(contentsKey);
  }

  /// Creates a PdfPKCS7 for RSA SHA1 signatures (adbe.x509.rsa_sha1).
  ///
  /// @param contentsKey the /Contents key
  /// @param certsKey the /Cert key (DER-encoded certificates)
  CraftPdfPKCS7.forRsaSha1(Uint8List contentsKey, Uint8List certsKey) {
    _signatureValue = contentsKey;
    _digestAlgorithmOid = CraftOID.sha1;
    _signatureMechanismOid = CraftOID.rsaSha1;

    // Parse certificates from certsKey
    _parseCertificates(certsKey);
  }

  /// Parses PKCS#7 SignedData structure.
  void _parseSignedData(Uint8List data) {
    try {
      final der = ASN1Parser(data);
      der.nextObject();
      if (data.skip(der.consumedBytes).any((b) => b != 0)) {
        throw FormatException('Unexpected data following CMS object');
      }
      // ContentInfo ::= SEQUENCE {
      //   contentType ContentType,
      //   content [0] EXPLICIT ANY DEFINED BY contentType }
      final contentInfo = ASN1Utils.parse(data);
      if (!contentInfo.isSequence) {
        throw FormatException('Expected SEQUENCE for ContentInfo');
      }

      final contentInfoElements = ASN1Utils.parseElements(contentInfo.content);
      if (contentInfoElements.length != 2) {
        throw FormatException('ContentInfo must have at least 2 elements');
      }

      // Check contentType is signedData
      final contentTypeOid = _parseOID(contentInfoElements[0].content);
      if (contentTypeOid != CraftOID.signedData) {
        throw FormatException('Expected signedData OID, got: $contentTypeOid');
      }

      // Get the SignedData content (tagged [0])
      if (!contentInfoElements[1].isContextSpecific ||
          contentInfoElements[1].tagNumber != 0) {
        throw FormatException('Expected context-specific tag for content');
      }

      final signedDataSeq = ASN1Utils.parse(contentInfoElements[1].content);
      if (signedDataSeq.tag != 0x30 ||
          signedDataSeq.totalLength != contentInfoElements[1].content.length) {
        throw FormatException('Expected SEQUENCE for SignedData');
      }

      final signedDataElements = ASN1Utils.parseElements(signedDataSeq.content);
      if (signedDataElements.length < 4 ||
          !signedDataElements[0].isInteger ||
          signedDataElements[1].tag != 0x31 ||
          signedDataElements[2].tag != 0x30 ||
          signedDataElements.last.tag != 0x31) {
        throw FormatException('Incomplete SignedData');
      }

      // SignedData ::= SEQUENCE {
      //   version CMSVersion,
      //   digestAlgorithms DigestAlgorithmIdentifiers,
      //   encapContentInfo EncapsulatedContentInfo,
      //   certificates [0] IMPLICIT CertificateSet OPTIONAL,
      //   crls [1] IMPLICIT RevocationInfoChoices OPTIONAL,
      //   signerInfos SignerInfos }

      int idx = 0;
      final advertisedDigests = <String>{};

      // Version
      if (signedDataElements[idx].isInteger) {
        _version = _parseInteger(signedDataElements[idx].content);
        idx++;
      }

      // DigestAlgorithms (SET)
      if (idx < signedDataElements.length && signedDataElements[idx].isSet) {
        final digestAlgos =
            ASN1Utils.parseElements(signedDataElements[idx].content);
        for (final algo in digestAlgos) {
          final fields = ASN1Utils.parseElements(algo.content);
          if (algo.tag != 0x30 || fields.isEmpty || !fields[0].isOid) {
            throw FormatException('Invalid digest algorithm');
          }
          advertisedDigests.add(_parseOID(fields[0].content));
        }
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
        if (encapContent.isEmpty ||
            !encapContent[0].isOid ||
            encapContent.length > 2) {
          throw FormatException('Invalid encapsulated content info');
        }
        _encapContentType = _parseOID(encapContent[0].content);
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
        if (signerInfos.length != 1)
          throw FormatException('Exactly one signer is required');
        _parseSignerInfo(signerInfos[0]);
        idx++;
      }
      if (idx != signedDataElements.length ||
          _signatureValue == null ||
          _digestAlgorithmOid == null ||
          _signatureMechanismOid == null ||
          _encapContentType == null ||
          !advertisedDigests.contains(_digestAlgorithmOid)) {
        throw FormatException('Incomplete CMS signature');
      }

      // Initialize message digest if we have encapsulated content or signed attributes
      if (_encapMessageContent != null || _digestAttr != null) {
        _messageDigest =
            CraftDigestAlgorithms.getMessageDigest(getDigestAlgorithmName());
      }
    } catch (e) {
      _parseFailed = true;
      _signatureValue = null;
    }
  }

  /// Parses a SignerInfo structure.
  void _parseSignerInfo(ASN1ParseResult signerInfo) {
    if (signerInfo.tag != 0x30) throw FormatException('Invalid SignerInfo tag');

    final elements = ASN1Utils.parseElements(signerInfo.content);
    if (elements.length < 5 || !elements[0].isInteger)
      throw FormatException('Incomplete SignerInfo');
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
          final serial = ASN1Parser(sidElements[1].encodedBytes).readSingle();
          if (sidElements.length != 2 || serial is! ASN1Integer) {
            throw FormatException('Invalid signer identifier');
          }
          _signerSerialNumber = serial.integer;
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
      _sigAttr = ASN1Utils.encodeTagged(0x31, elements[idx].content);
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
    if (idx < elements.length &&
        elements[idx].isContextSpecific &&
        elements[idx].tagNumber == 1) idx++; // unsigned attributes
    if (idx != elements.length ||
        _signatureValue == null ||
        (_signerIssuer == null && _signerSubjectKeyIdentifier == null)) {
      throw FormatException('Incomplete SignerInfo');
    }
  }

  /// Parses signed attributes.
  void _parseSignedAttributes(Uint8List content) {
    final attrs = ASN1Utils.parseElements(content);
    var digestFound = false, contentTypeFound = false;
    for (final attr in attrs) {
      if (!attr.isSequence) throw FormatException('Invalid signed attribute');

      final attrElements = ASN1Utils.parseElements(attr.content);
      if (attrElements.length != 2 || !attrElements[1].isSet)
        throw FormatException('Invalid attribute values');

      if (!attrElements[0].isOid)
        throw FormatException('Invalid attribute identifier');
      final attrOid = _parseOID(attrElements[0].content);

      // Message digest attribute
      if (attrOid == CraftOID.messageDigest) {
        final values = ASN1Utils.parseElements(attrElements[1].content);
        if (digestFound || values.length != 1 || !values[0].isOctetString) {
          throw FormatException('Invalid or repeated messageDigest');
        }
        digestFound = true;
        _digestAttr = values[0].content;
      } else if (attrOid == CraftOID.contentType) {
        final values = ASN1Utils.parseElements(attrElements[1].content);
        if (contentTypeFound ||
            values.length != 1 ||
            !values[0].isOid ||
            _parseOID(values[0].content) != _encapContentType) {
          throw FormatException('Invalid or repeated contentType');
        }
        contentTypeFound = true;
      }
    }
    if (!digestFound || !contentTypeFound)
      throw FormatException('Required signed attributes are absent');
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
      if (_parseFailed || _signatureValue == null || _isTsp) return false;
      final digestName = getDigestAlgorithmName();
      final expectedMechanism =
          CraftSignatureMechanisms.getSignatureMechanismOid('RSA', digestName);
      if (_signatureMechanismOid != CraftOID.rsa &&
          _signatureMechanismOid != expectedMechanism &&
          !(_signatureMechanismOid == CraftOID.rsaSha1 &&
              digestName == 'SHA1')) {
        return false;
      }
      if (_filterSubtype == CraftPdfName.adbePkcs7Sha1 &&
          !_legacyContentMatches()) return false;
      if (_encapMessageContent != null) {
        if (!_receivedContent) return false;
        if (_filterSubtype == CraftPdfName.adbePkcs7Sha1) {
          final digest = CraftDigestAlgorithms.getMessageDigest('SHA1')
            ..update(_verificationContent.toBytes());
          if (!_arraysEqual(digest.digest(), _encapMessageContent!))
            return false;
        } else if (_filterSubtype == CraftPdfName.adbePkcs7Detached ||
            _filterSubtype == CraftPdfName.etsiCadesDetached ||
            !_arraysEqual(
                _verificationContent.toBytes(), _encapMessageContent!)) {
          return false;
        }
      }

      // 1. Find Signing Certificate
      _findSigningCertificate();
      if (_signCert == null) {
        return false;
      }

      // 2. Prepare message digest
      if (_messageDigest == null) {
        _messageDigest =
            CraftDigestAlgorithms.getMessageDigest(getDigestAlgorithmName());
      }

      // Validate the document digest before authenticating signed attributes.
      if (_sigAttr != null) {
        if (_digestAttr == null) return false;
        if (_encapMessageContent != null) {
          _messageDigest!.reset();
          _messageDigest!.update(_encapMessageContent!);
          _calculatedContentDigest = _messageDigest!.digest();
        } else if (!_receivedContent) {
          return false;
        }
        _calculatedContentDigest ??= _currentContentDigest();
        if (!_arraysEqual(_calculatedContentDigest!, _digestAttr!))
          return false;
      }

      // 4. Verify Signature (Authenticity)
      final publicKeyInfo = _signCert!.getPublicKey();
      final publicKey =
          CraftSignUtils.parsePublicKeyFromSubjectPublicKeyInfo(publicKeyInfo);

      if (publicKey == null) {
        return false;
      }

      final signer = CraftSignUtils.createSigner(
          '${getDigestAlgorithmName()}withRSA', publicKey);

      if (signer == null) {
        return false;
      }

      final sig = RSASignature(_signatureValue!);

      if (_sigAttr != null) {
        _verifyResult = signer.verifySignature(_sigAttr!, sig);
      } else if (_encapMessageContent != null) {
        _verifyResult = signer.verifySignature(_encapMessageContent!, sig);
      } else if (_receivedContent) {
        _verifyResult =
            signer.verifySignature(_verificationContent.toBytes(), sig);
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
    if (_certsDer.length == 1 &&
        _signerIssuer == null &&
        _signerSubjectKeyIdentifier == null) {
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
  int formatVersion() => _version;

  /// Gets the version of the PKCS#7 "SignerInfo" object.
  int getSigningInfoVersion() => _signerVersion;

  /// Gets the digest algorithm OID.
  String? getDigestAlgorithmOid() => _digestAlgorithmOid;

  /// Gets the digest algorithm name.
  String getDigestAlgorithmName() {
    if (_digestAlgorithmOid == null) {
      return 'SHA-256';
    }
    return CraftDigestAlgorithms.getDigest(_digestAlgorithmOid!);
  }

  /// Gets the signature mechanism OID.
  String? getSignatureMechanismOid() => _signatureMechanismOid;

  /// Gets the signature mechanism name.
  String getSignatureMechanismName() {
    if (_signatureMechanismOid == null) {
      return 'SHA256withRSA';
    }

    switch (_signatureMechanismOid) {
      case CraftOID.ed25519:
        return 'Ed25519';
      case CraftOID.ed448:
        return 'Ed448';
      case CraftOID.rsassaPss:
        return 'RSASSA-PSS';
      default:
        return CraftSignatureMechanisms.getMechanism(
            _signatureMechanismOid!, getDigestAlgorithmName());
    }
  }

  /// Gets the signature algorithm name (disregarding digest).
  String getSignatureAlgorithmName() {
    if (_signatureMechanismOid == null) {
      return 'RSA';
    }
    return CraftSignatureMechanisms.getAlgorithm(_signatureMechanismOid!);
  }

  /// Gets the filter subtype.
  CraftPdfName? getFilterSubtype() => _filterSubtype;

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
    RangeError.checkValidRange(offset, offset + len, buf.length);
    _receivedContent = true;
    _verifyResult = null;
    _calculatedContentDigest = null;
    _messageDigest ??=
        CraftDigestAlgorithms.getMessageDigest(getDigestAlgorithmName());
    _messageDigest!.update(buf, offset, len);
    _verificationContent.add(buf.sublist(offset, offset + len));
  }

  Uint8List _currentContentDigest() {
    final digest =
        CraftDigestAlgorithms.getMessageDigest(getDigestAlgorithmName())
          ..update(_verificationContent.toBytes());
    return digest.digest();
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
      final oid = CraftSignatureMechanisms.getSignatureMechanismOid(
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
      ASN1Utils.createOID(CraftOID.contentType),
      ASN1Utils.createSet([
        ASN1Utils.createOID(CraftOID.data),
      ]),
    ]));

    // Signing time attribute
    if (_signDate != null) {
      attrs.add(ASN1Utils.createSequence([
        ASN1Utils.createOID(CraftOID.signingTime),
        ASN1Utils.createSet([
          ASN1Utils.createUtcTime(_signDate!),
        ]),
      ]));
    }

    // Message digest attribute
    attrs.add(ASN1Utils.createSequence([
      ASN1Utils.createOID(CraftOID.messageDigest),
      ASN1Utils.createSet([
        ASN1Utils.createOctetString(secondDigest),
      ]),
    ]));

    return ASN1Utils.createSet(attrs);
  }

  /// Gets the encoded PKCS#7 object.
  Future<Uint8List> getEncodedPKCS7(
    Uint8List secondDigest, {
    CraftTSAClient? tsaClient,
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
    encapContent.add(ASN1Utils.createOID(CraftOID.data));
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
          other.add(ASN1Utils.createOID(CraftOID.ocspResponse));
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
    elements.add(ASN1Utils.createOID(CraftOID.signedData));
    elements.add(ASN1Utils.encodeTagged(0xA0, content));

    return ASN1Utils.createSequence(elements);
  }

  /// Builds the SignerInfo structure.
  Future<Uint8List> _buildSignerInfo(
      Uint8List secondDigest, CraftTSAClient? tsaClient) async {
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
      ASN1Utils.createOID(_signatureMechanismOid ?? CraftOID.rsaSha256),
      ASN1Utils.createNull(),
    ]));

    // SignatureValue
    elements.add(ASN1Utils.createOctetString(_signatureValue!));

    // UnsignedAttributes [1] IMPLICIT
    if (tsaClient != null) {
      final tsaToken = await tsaClient.getTimeStampToken(_signatureValue!);

      final attrContent = <Uint8List>[];
      attrContent.add(ASN1Utils.createOID(CraftOID.signatureTimeStampToken));
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

  bool _legacyContentMatches() {
    final content = _encapMessageContent;
    return _receivedContent &&
        content != null &&
        content.length == 20 &&
        _arraysEqual(
            CraftDigestAlgorithms.digestBytes(
                _verificationContent.toBytes(), 'SHA1'),
            content);
  }

  /// Verifies the message digest.
  ///
  /// @return true if the digest matches
  bool verifyDigest() {
    if (_parseFailed ||
        !_receivedContent ||
        _digestAttr == null ||
        _messageDigest == null) {
      return false;
    }

    if (_filterSubtype == CraftPdfName.adbePkcs7Sha1 &&
        !_legacyContentMatches()) return false;
    final content = _encapMessageContent;
    final calculatedDigest = content == null
        ? (_calculatedContentDigest ??= _currentContentDigest())
        : CraftDigestAlgorithms.digestBytes(content, getDigestAlgorithmName());

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
