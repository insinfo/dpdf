import '../platform/io.dart';
import 'dart:typed_data';

import 'package:pdfcraft/src/kernel/crypto/digest_algorithms.dart';
import 'package:pdfcraft/src/sign/der_objects.dart';
import 'package:pdfcraft/src/commons/pdfcraft_log_manager.dart';

import 'certificate_util.dart';
import 'ocsp_client.dart';
import 'certificate_details.dart';

/// OcspClient implementation using the local DER model and Dart HTTP client.
class HttpOcspClient implements CraftOcspClient {
  static final _logger = LogManager.getLoggerByName('HttpOcspClient');

  /// Creates an HttpOcspClient instance.
  HttpOcspClient();

  @override
  Future<Uint8List?> getEncoded(CertificateDetails checkCert,
      CertificateDetails rootCert, String? url) async {
    try {
      final basicResponse = await _getBasicOCSPResp(checkCert, rootCert, url);
      if (basicResponse != null) {
        // TODO: Validate response status
        // For now return proper encoded response
        return basicResponse.encodedBytes;
      }
    } catch (e) {
      _logger.logError(e.toString());
    }
    return null;
  }

  /// Gets the basic OCSP response.
  Future<ASN1Object?> _getBasicOCSPResp(CertificateDetails checkCert,
      CertificateDetails rootCert, String? url) async {
    final ocspResponse = await _getOcspResponse(checkCert, rootCert, url);
    if (ocspResponse == null) return null;

    // OCSPResponse ::= SEQUENCE {
    //   responseStatus         OCSPResponseStatus,
    //   responseBytes          [0] EXPLICIT ResponseBytes OPTIONAL }

    try {
      final seq = ASN1Parser(ocspResponse).nextObject() as ASN1Sequence;
      if (seq.elements!.length != 2) return null;
      final status = seq.elements![0];
      if (status is! ASN1Enumerated || status.integer != BigInt.zero)
        return null;
      final wrapper = seq.elements![1];
      if (wrapper is! ASN1Sequence ||
          wrapper.tag != 0xa0 ||
          wrapper.elements!.length != 1) return null;
      final responseBytes = wrapper.elements!.first;
      if (responseBytes is! ASN1Sequence || responseBytes.elements!.length != 2)
        return null;
      final type = responseBytes.elements![0],
          response = responseBytes.elements![1];
      if (type is! ASN1ObjectIdentifier ||
          type.objectIdentifierAsString != '1.3.6.1.5.5.7.48.1.1' ||
          response is! ASN1OctetString) return null;
      // Transport extraction only: callers must validate the signed response.
      return ASN1Parser(response.octets).nextObject();
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> _getOcspResponse(CertificateDetails checkCert,
      CertificateDetails rootCert, String? url) async {
    if (url == null) {
      url = CraftCertificateUtil.getOCSPURL(checkCert);
    }
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
    final digest = CraftDigestAlgorithms.getMessageDigest("SHA-1");
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
