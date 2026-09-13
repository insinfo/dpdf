import '../platform/io.dart';
import 'dart:typed_data';

import 'package:dpdf/src/kernel/crypto/digest_algorithms.dart';
import 'package:dpdf/src/sign/der_objects.dart';
import 'package:dpdf/src/commons/dpdf_log_manager.dart';

import 'certificate_util.dart';
import 'ocsp_client.dart';
import 'certificate_details.dart';

/// `OCSPResponseStatus` of RFC 6960 section 4.2.1.
enum OcspResponseStatus {
  /// Response has valid confirmations.
  successful(0),

  /// Illegal confirmation request.
  malformedRequest(1),

  /// Internal error in issuer.
  internalError(2),

  /// Try again later.
  tryLater(3),

  /// Must sign the request.
  sigRequired(5),

  /// Request unauthorized.
  unauthorized(6);

  const OcspResponseStatus(this.value);

  /// The ENUMERATED value carried on the wire.
  final int value;

  /// The status for [value], or null when the responder used the unassigned
  /// value 4 or a value outside the enumeration.
  static OcspResponseStatus? fromValue(int value) {
    for (final status in OcspResponseStatus.values) {
      if (status.value == value) return status;
    }
    return null;
  }
}

/// A responder answered with something other than `successful`.
class OcspResponseStatusException implements Exception {
  /// The decoded status, or null when the responder used a reserved value.
  final OcspResponseStatus? status;

  /// The raw ENUMERATED value.
  final int value;

  OcspResponseStatusException(this.status, this.value);

  @override
  String toString() =>
      'OCSP responder returned ${status?.name ?? 'unknown status'} ($value)';
}

/// OcspClient implementation using the local DER model and Dart HTTP client.
class HttpOcspClient implements OcspClient {
  static final _logger = LogManager.getLoggerByName('HttpOcspClient');

  /// `id-pkix-ocsp-basic`, the only response type defined by RFC 6960.
  static const String basicResponseOid = '1.3.6.1.5.5.7.48.1.1';

  OcspResponseStatus? _lastStatus;

  /// Creates an HttpOcspClient instance.
  HttpOcspClient();

  /// The `responseStatus` of the last response that was parsed, or null when
  /// no response arrived or its status could not be decoded.
  OcspResponseStatus? getLastResponseStatus() => _lastStatus;

  @override
  Future<Uint8List?> getEncoded(CertificateDetails checkCert,
      CertificateDetails rootCert, String? url) async {
    try {
      final basicResponse = await _getBasicOCSPResp(checkCert, rootCert, url);
      if (basicResponse != null) {
        return basicResponse.encodedBytes;
      }
    } catch (e) {
      _logger.logError(e.toString());
    }
    return null;
  }

  /// Reads the `responseStatus` of an OCSPResponse, RFC 6960 section 4.2.1.
  ///
  /// Throws [FormatException] when the first element is not an ENUMERATED
  /// holding a value the syntax allows.
  static int readResponseStatusValue(ASN1Sequence response) {
    final elements = response.elements;
    if (elements == null || elements.isEmpty) {
      throw const FormatException('OCSPResponse has no responseStatus');
    }
    final status = elements.first;
    if (status is! ASN1Enumerated || status.integer == null) {
      throw const FormatException(
          'OCSPResponse responseStatus is not an ENUMERATED');
    }
    final value = status.integer!;
    if (value < BigInt.zero || value > BigInt.from(255)) {
      throw const FormatException('OCSPResponse responseStatus out of range');
    }
    return value.toInt();
  }

  /// Extracts the BasicOCSPResponse out of an OCSPResponse.
  ///
  /// RFC 6960 section 4.2.1 only permits `responseBytes` when `responseStatus`
  /// is `successful`, so the status is checked first and any other value is
  /// reported as an [OcspResponseStatusException] instead of being mistaken
  /// for a usable response.
  static ASN1Object parseBasicResponse(Uint8List encodedResponse) {
    final root = ASN1Parser(encodedResponse).nextObject();
    if (root is! ASN1Sequence || root is ASN1Set) {
      throw const FormatException('OCSPResponse is not a SEQUENCE');
    }
    final statusValue = readResponseStatusValue(root);
    final status = OcspResponseStatus.fromValue(statusValue);
    if (status != OcspResponseStatus.successful) {
      throw OcspResponseStatusException(status, statusValue);
    }
    final elements = root.elements!;
    if (elements.length != 2) {
      throw const FormatException(
          'Successful OCSPResponse carries no responseBytes');
    }
    final wrapper = elements[1];
    if (wrapper is! ASN1Sequence ||
        wrapper.tag != 0xa0 ||
        wrapper.elements!.length != 1) {
      throw const FormatException('Malformed OCSPResponse responseBytes');
    }
    final responseBytes = wrapper.elements!.first;
    if (responseBytes is! ASN1Sequence || responseBytes.elements!.length != 2) {
      throw const FormatException('Malformed OCSP ResponseBytes');
    }
    final type = responseBytes.elements![0],
        response = responseBytes.elements![1];
    if (type is! ASN1ObjectIdentifier ||
        type.objectIdentifierAsString != basicResponseOid) {
      throw const FormatException('Unsupported OCSP responseType');
    }
    if (response is! ASN1OctetString) {
      throw const FormatException('OCSP response is not an OCTET STRING');
    }
    // Transport extraction only: callers must validate the signed response.
    return ASN1Parser(response.octets).nextObject();
  }

  /// Gets the basic OCSP response.
  Future<ASN1Object?> _getBasicOCSPResp(CertificateDetails checkCert,
      CertificateDetails rootCert, String? url) async {
    final ocspResponse = await _getOcspResponse(checkCert, rootCert, url);
    if (ocspResponse == null) return null;

    // OCSPResponse ::= SEQUENCE {
    //   responseStatus         OCSPResponseStatus,
    //   responseBytes          [0] EXPLICIT ResponseBytes OPTIONAL }

    _lastStatus = null;
    try {
      final basic = parseBasicResponse(ocspResponse);
      _lastStatus = OcspResponseStatus.successful;
      return basic;
    } on OcspResponseStatusException catch (e) {
      _lastStatus = e.status;
      _logger.logError(e.toString());
      return null;
    } catch (e) {
      _logger.logError('Unreadable OCSP response: $e');
      return null;
    }
  }

  Future<Uint8List?> _getOcspResponse(CertificateDetails checkCert,
      CertificateDetails rootCert, String? url) async {
    url ??= CertificateUtil.getOCSPURL(checkCert);
    if (url == null) return null;

    // Generate Request
    _logger.logInfo("Getting OCSP from $url");
    final request =
        _generateOCSPRequest(checkCert, rootCert, checkCert.getSerialNumber());

    // Send Request
    final client = HttpClient();
    try {
      final uri = Uri.parse(url);
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType('application', 'ocsp-request');
      req.add(request);
      final resp = await req.close();

      if (resp.statusCode == HttpStatus.ok) {
        final builder = BytesBuilder();
        await resp.forEach(builder.add);
        return builder.toBytes();
      }
    } catch (e) {
      _logger.logError(e.toString());
    } finally {
      client.close();
    }
    return null;
  }

  Uint8List _generateOCSPRequest(CertificateDetails checkCert,
      CertificateDetails issuerCert, BigInt serialNumber) {
    // 1. Get Hash Algorithm (SHA-1)
    // OID: 1.3.14.3.2.26
    final algId = ASN1Sequence();
    algId.add(ASN1ObjectIdentifier.fromName("1.3.14.3.2.26"));
    algId.add(ASN1Null());

    // 2. Issuer Name Hash
    // Hash of the Issuer's DN in the checked certificate
    final issuerNameBytes = checkCert.getIssuerX500Name();
    final issuerNameHash = _calculateSha1(issuerNameBytes);

    // 3. Issuer Key Hash
    // Hash of the Issuer's Public Key (BIT STRING value, excluding tag/len)
    final spkiBytes = issuerCert.getPublicKey();
    // Helper to get key bytes from SPKI
    final issuerKeyBytes = _getPublicKeyBytes(spkiBytes);
    final issuerKeyHash = _calculateSha1(issuerKeyBytes);

    // 4. Serial Number
    final serial = ASN1Integer(serialNumber);

    // 5. CertID
    final certId = ASN1Sequence();
    certId.add(algId);
    certId.add(ASN1OctetString(octets: issuerNameHash));
    certId.add(ASN1OctetString(octets: issuerKeyHash));
    certId.add(serial);

    // 6. Request
    final request = ASN1Sequence();
    request.add(certId);

    // 7. RequestList
    final requestList = ASN1Sequence();
    requestList.add(request);

    // 8. TBSRequest
    final tbsRequest = ASN1Sequence();
    // Version is default (0)
    // RequestorName omitted
    tbsRequest.add(requestList);
    // RequestExtensions omitted

    // 9. OCSPRequest
    final ocspRequest = ASN1Sequence();
    ocspRequest.add(tbsRequest);
    // OptionalSignature omitted

    return ocspRequest.encodedBytes ?? Uint8List(0);
  }

  Uint8List _calculateSha1(Uint8List input) {
    final digest = DigestAlgorithms.getMessageDigest("SHA-1");
    // DigestAlgorithms wrapper usually exposes process or digestWithInput or similar
    return digest.digestWithInput(input);
  }

  Uint8List _getPublicKeyBytes(Uint8List spkiBytes) {
    try {
      final asn1Parser = ASN1Parser(spkiBytes);
      final spki = asn1Parser.nextObject() as ASN1Sequence;
      // SubjectPublicKeyInfo ::= SEQUENCE {
      //     algorithm AlgorithmIdentifier,
      //     subjectPublicKey BIT STRING }
      if (spki.elements != null && spki.elements!.length > 1) {
        final bitString = spki.elements![1] as ASN1BitString;
        return Uint8List.fromList(bitString.stringValues);
      }
    } catch (e) {
      // ignore
    }
    return Uint8List(0);
  }
}
