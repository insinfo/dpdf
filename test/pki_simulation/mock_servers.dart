import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart'; // Check imports

class MockTsaServer {
  HttpServer? _server;
  final int port;
  final AsymmetricKeyPair<PublicKey, PrivateKey> keyPair; // TSA signing key
  final Uint8List certBytes;

  MockTsaServer(this.port, this.keyPair, this.certBytes);

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    await _server?.close();
  }

  void _handleRequest(HttpRequest request) async {
    if (request.method == 'POST') {
      final content = await request.expand((b) => b).toList();
      // Parse TimeStampReq
      // Assuming we just reply with success and current time
      final resp = _createResponse(Uint8List.fromList(content));
      request.response.headers.contentType =
          ContentType('application', 'timestamp-reply');
      request.response.add(resp);
    } else {
      request.response.statusCode = HttpStatus.methodNotAllowed;
    }
    await request.response.close();
  }

  Uint8List _createResponse(Uint8List reqBytes) {
    // 1. Status: Granted (0)
    final statusInfo = ASN1Sequence();
    statusInfo.add(ASN1Integer(BigInt.zero)); // status: granted

    // 2. TimeStampToken
    // ContentInfo (id-signedData, SignedData)
    // SignedData -> EncapsulatedContentInfo (id-ct-TSTInfo, TSTInfo)

    // TSTInfo construction
    final tstInfo = ASN1Sequence();
    tstInfo.add(ASN1Integer(BigInt.one)); // version 1
    tstInfo.add(ASN1ObjectIdentifier.fromIdentifierString(
        '2.5.4.3')); // Policy OID (dummy)

    // MessageImprint (Extract from reqBytes or dummy)
    // For simplicity, we just put a dummy hash matching request algo
    final msgImprint = ASN1Sequence();
    final algo = ASN1Sequence();
    algo.add(ASN1ObjectIdentifier.fromIdentifierString(
        '2.16.840.1.101.3.4.2.1')); // SHA-256
    algo.add(ASN1Null());
    msgImprint.add(algo);
    msgImprint.add(ASN1OctetString(octets: Uint8List(32))); // Dummy hash
    tstInfo.add(msgImprint);

    // SerialNumber
    tstInfo
        .add(ASN1Integer(BigInt.from(DateTime.now().millisecondsSinceEpoch)));

    // GenTime
    tstInfo.add(ASN1GeneralizedTime(DateTime.now()));

    // Sign TSTInfo
    // ... This is getting complex to implement perfectly correct CMS.
    // We'll return a minimal valid structure or just what we have.
    // For PdfPKCS7 testing, we mainly need the token to exist and have a structure.

    // Shortcuts: We will return a construct that `PdfPKCS7` won't reject if we don't fully validate it yet.
    // But PdfSigner will try to embed it.

    // Let's rely on basic ASN1 wrapping.

    final token = ASN1Sequence();
    token.add(ASN1ObjectIdentifier.fromIdentifierString(
        '1.2.840.113549.1.7.2')); // signedData
    // ... Content ...

    final resp = ASN1Sequence();
    resp.add(statusInfo);
    // resp.add(token); // Optional

    return resp.encode();
  }
}

class MockOcspServer {
  HttpServer? _server;
  final int port;

  MockOcspServer(this.port);

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    await _server?.close();
  }

  void _handleRequest(HttpRequest request) async {
    if (request.method == 'POST') {
      final resp = _createResponse();
      request.response.headers.contentType =
          ContentType('application', 'ocsp-response');
      request.response.add(resp);
    }
    await request.response.close();
  }

  Uint8List _createResponse() {
    // OCSPResponse: successful(0)
    final resp = ASN1Sequence();
    resp.add(ASN1Enumerated(0)); // proper success

    // ResponseBytes
    final respBytes = ASN1Sequence();
    respBytes.add(ASN1ObjectIdentifier.fromIdentifierString(
        '1.3.6.1.5.5.7.48.1.1')); // id-pkix-ocsp-basic

    final basicResp = ASN1Sequence();
    // ... BasicOCSPResponse content ...

    respBytes.add(ASN1OctetString(octets: basicResp.encode()));

    // [0] EXPLICIT ResponseBytes
    // resp.add(tagged...);

    return resp.encode();
  }
}
