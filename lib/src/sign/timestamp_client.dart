import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';

import '../platform/io.dart';
import 'tsa_client.dart';
import 'external_digest.dart';
import 'digest_algorithms.dart';
import 'asn1_utils.dart';

/// Builds timestamp requests and parses RFC 3161 response envelopes.
///
/// HTTP transport and validation of the returned timestamp's trust and imprint
/// are not implemented by this class.
class TimestampClient implements CraftTSAClient {
  /// The URL of the TSA service.
  final String _tsaUrl;

  /// The username for authentication (optional).
  final String? _username;

  /// The password for authentication (optional).
  final String? _password;

  /// The digest algorithm to use.
  final String _digestAlgorithm;

  /// Estimated token size.
  int _tokenSizeEstimate;

  /// Creates a TSA client.
  ///
  /// @param tsaUrl the URL of the TSA service
  /// @param username optional username for basic authentication
  /// @param password optional password for basic authentication
  /// @param digestAlgorithm the digest algorithm (default: SHA-256)
  /// @param tokenSizeEstimate estimated size of the token (default: 4096)
  TimestampClient(
    this._tsaUrl, {
    String? username,
    String? password,
    String digestAlgorithm = 'SHA-256',
    int tokenSizeEstimate = 4096,
  })  : _username = username,
        _password = password,
        _digestAlgorithm = digestAlgorithm,
        _tokenSizeEstimate = tokenSizeEstimate;

  @override
  int getTokenSizeEstimate() => _tokenSizeEstimate;

  /// Sets the estimated token size.
  void setTokenSizeEstimate(int estimate) {
    _tokenSizeEstimate = estimate;
  }

  @override
  SigningDigest getMessageDigest() {
    return CraftDigestAlgorithms.getMessageDigest(_digestAlgorithm);
  }

  @override
  Future<Uint8List> getTimeStampToken(Uint8List imprint) async {
    final request = buildTimeStampRequest(imprint);
    final client = HttpClient();
    try {
      final httpRequest = await client.postUrl(Uri.parse(_tsaUrl));
      httpRequest.headers.contentType =
          ContentType('application', 'timestamp-query');
      httpRequest.headers.set('Accept', 'application/timestamp-reply');
      final authorization = getAuthorizationHeader();
      if (authorization != null) {
        httpRequest.headers.set('Authorization', authorization);
      }
      httpRequest.add(request);
      final response = await httpRequest.close();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
            'Timestamp authority returned HTTP ${response.statusCode}.');
      }
      final bytes = BytesBuilder(copy: false);
      await response.forEach(bytes.add);
      final token = parseTimeStampResponse(bytes.toBytes());
      if (token.length > _tokenSizeEstimate) {
        _tokenSizeEstimate = token.length;
      }
      return token;
    } finally {
      client.close();
    }
  }

  /// Builds an RFC 3161 TimeStampRequest.
  ///
  /// TimeStampReq ::= SEQUENCE  {
  ///    version                  INTEGER  { v1(1) },
  ///    messageImprint           MessageImprint,
  ///    reqPolicy                TSAPolicyId              OPTIONAL,
  ///    nonce                    INTEGER                  OPTIONAL,
  ///    certReq                  BOOLEAN                  DEFAULT FALSE,
  ///    extensions               [0] IMPLICIT Extensions  OPTIONAL
  /// }
  ///
  /// MessageImprint ::= SEQUENCE  {
  ///    hashAlgorithm            AlgorithmIdentifier,
  ///    hashedMessage            OCTET STRING
  /// }
  Uint8List buildTimeStampRequest(Uint8List imprint) {
    // Get algorithm OID
    final algorithmOid =
        CraftDigestAlgorithms.getAllowedDigest(_digestAlgorithm);
    if (algorithmOid == null) {
      throw ArgumentError('Unknown digest algorithm: $_digestAlgorithm');
    }

    // Build AlgorithmIdentifier
    final algorithmIdentifier = ASN1Utils.createSequence([
      ASN1Utils.createOID(algorithmOid),
      ASN1Utils.createNull(), // parameters (NULL for most hash algorithms)
    ]);

    // Build MessageImprint
    final messageImprint = ASN1Utils.createSequence([
      algorithmIdentifier,
      ASN1Utils.createOctetString(imprint),
    ]);

    // Generate nonce
    final nonce = _generateNonce();

    // Build TimeStampReq
    final timeStampReq = ASN1Utils.createSequence([
      ASN1Utils.createIntegerFromInt(1), // version 1
      messageImprint,
      // reqPolicy - optional, not included
      ASN1Utils.createInteger(BigInt.from(nonce)), // nonce
      ASN1Utils.createBoolean(true), // certReq - request certificates
    ]);

    return timeStampReq;
  }

  /// Parses a time stamp response.
  ///
  /// @param response the DER-encoded response
  /// @return the time stamp token (DER-encoded)
  Uint8List parseTimeStampResponse(Uint8List response) {
    final root = _ResponseDer.read(response, 0, response.length);
    if (root.tag != 0x30 || root.end != response.length) {
      throw const FormatException(
          'Timestamp response must be one DER sequence');
    }
    final fields = root.children(response);
    if (fields.isEmpty || fields.length > 2 || fields.first.tag != 0x30) {
      throw const FormatException(
          'Timestamp response has an invalid field layout');
    }
    final statusFields = fields.first.children(response);
    if (statusFields.isEmpty ||
        statusFields.first.tag != 2 ||
        statusFields.first.end - statusFields.first.content != 1) {
      throw const FormatException(
          'Timestamp status must be a one-byte integer');
    }
    final status = response[statusFields.first.content];
    if (status != 0 && status != 1) {
      throw FormatException(
          'Timestamp authority did not grant the request: $status');
    }
    var optional = 1;
    if (optional < statusFields.length && statusFields[optional].tag == 0x30) {
      final messages = statusFields[optional++].children(response);
      if (messages.isEmpty || messages.any((value) => value.tag != 0x0c)) {
        throw const FormatException(
            'Timestamp status text has an invalid structure');
      }
      for (final message in messages) {
        utf8.decode(response.sublist(message.content, message.end));
      }
    }
    if (optional < statusFields.length && statusFields[optional].tag == 3) {
      final flags = statusFields[optional++];
      final size = flags.end - flags.content;
      if (size == 0 ||
          response[flags.content] > 7 ||
          (size == 1 && response[flags.content] != 0) ||
          (size > 1 &&
              (response[flags.end - 1] &
                      ((1 << response[flags.content]) - 1)) !=
                  0)) {
        throw const FormatException('Timestamp failure flags are malformed');
      }
    }
    if (optional != statusFields.length || fields.length != 2) {
      throw const FormatException('Timestamp response has no usable token');
    }
    final token = fields[1];
    if (token.tag != 0x30) {
      throw const FormatException('Timestamp token must be CMS ContentInfo');
    }
    final cms = token.children(response);
    const signedData = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 1, 7, 2];
    if (cms.length != 2 ||
        cms[0].tag != 6 ||
        cms[1].tag != 0xa0 ||
        cms[0].end - cms[0].content != signedData.length) {
      throw const FormatException(
          'Timestamp token has an invalid CMS envelope');
    }
    for (var i = 0; i < signedData.length; i++) {
      if (response[cms[0].content + i] != signedData[i]) {
        throw const FormatException(
            'Timestamp token content type is not signedData');
      }
    }
    final payload = cms[1].children(response);
    if (payload.length != 1 || payload.first.tag != 0x30) {
      throw const FormatException(
          'Timestamp signedData must be explicitly wrapped');
    }
    return Uint8List.fromList(response.sublist(token.start, token.end));
  }

  /// Generates a random nonce value.
  int _generateNonce() {
    // RFC 3161 nonce values must make replaying a captured request impractical.
    // Random.secure is backed by the platform cryptographic random source.
    return Random.secure().nextInt(1 << 31);
  }

  /// Gets the URL of the TSA service.
  String getUrl() => _tsaUrl;

  /// Gets the digest algorithm.
  String getDigestAlgorithm() => _digestAlgorithm;

  /// Gets the authentication credentials as a Base64-encoded Basic auth header.
  String? getAuthorizationHeader() {
    if (_username == null || _password == null) {
      return null;
    }
    final credentials = base64Encode(utf8.encode('$_username:$_password'));
    return 'Basic $credentials';
  }
}

/// A simple TSA client that supports common TSA services.
class SimpleTSAClient extends TimestampClient {
  /// Creates a TSA client for a well-known TSA service.
  ///
  /// @param tsaUrl the TSA URL
  SimpleTSAClient(String tsaUrl) : super(tsaUrl);

  /// Creates a TSA client for a well-known free TSA service.
  factory SimpleTSAClient.freeTsa() {
    return SimpleTSAClient('https://freetsa.org/tsr');
  }

  /// Creates a TSA client for DigiCert TSA.
  factory SimpleTSAClient.digiCert() {
    return SimpleTSAClient('http://timestamp.digicert.com');
  }

  /// Creates a TSA client for Symantec/Verisign TSA.
  factory SimpleTSAClient.symantec() {
    return SimpleTSAClient(
        'http://sha256timestamp.ws.symantec.com/sha256/timestamp');
  }

  /// Creates a TSA client for GlobalSign TSA.
  factory SimpleTSAClient.globalSign() {
    return SimpleTSAClient('http://timestamp.globalsign.com/tsa/r6advanced1');
  }
}

// A bounded reader for the response envelope. It deliberately does not verify
// the CMS signature, certificate chain, timestamp imprint or nonce.
class _ResponseDer {
  final int tag;
  final int start;
  final int content;
  final int end;
  const _ResponseDer(this.tag, this.start, this.content, this.end);

  static _ResponseDer read(Uint8List bytes, int offset, int limit) {
    final start = offset;
    if (limit - offset < 2) {
      throw const FormatException('Truncated timestamp DER header');
    }
    final tag = bytes[offset++];
    if ((tag & 31) == 31 || tag == 0) {
      throw const FormatException('Unsupported timestamp DER tag');
    }
    var length = bytes[offset++];
    if (length >= 128) {
      final count = length & 127;
      if (count == 0 ||
          count > 4 ||
          count > limit - offset ||
          bytes[offset] == 0) {
        throw const FormatException('Invalid timestamp DER length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = length * 256 + bytes[offset++];
      }
      if (length < 128) {
        throw const FormatException('Nonminimal timestamp DER length');
      }
    }
    if (length > limit - offset) {
      throw const FormatException('Timestamp DER value exceeds its container');
    }
    return _ResponseDer(tag, start, offset, offset + length);
  }

  List<_ResponseDer> children(Uint8List bytes) {
    final result = <_ResponseDer>[];
    var position = content;
    while (position < end) {
      final child = read(bytes, position, end);
      result.add(child);
      position = child.end;
    }
    return result;
  }
}
