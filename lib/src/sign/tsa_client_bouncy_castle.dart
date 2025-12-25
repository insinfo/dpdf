import 'dart:typed_data';
import 'dart:convert';

import 'i_tsa_client.dart';
import 'i_external_digest.dart';
import 'digest_algorithms.dart';
import 'asn1_utils.dart';

/// Implementation of ITSAClient for RFC 3161 Time Stamp Authority.
///
/// This client sends a time stamp request to a TSA server and retrieves
/// the time stamp token.
class TSAClientBouncyCastle implements ITSAClient {
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
  TSAClientBouncyCastle(
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
  IMessageDigest getMessageDigest() {
    return DigestAlgorithms.getMessageDigest(_digestAlgorithm);
  }

  @override
  Future<Uint8List> getTimeStampToken(Uint8List imprint) async {
    // Build the TimeStampRequest
    final request = buildTimeStampRequest(imprint);

    // TODO: Send HTTP request to TSA
    // This would require an HTTP client (http package)
    // For now, return the request for testing purposes
    throw UnimplementedError(
        'TSA HTTP request not yet implemented. URL: $_tsaUrl, Request size: ${request.length}');
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
    final algorithmOid = DigestAlgorithms.getAllowedDigest(_digestAlgorithm);
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
    // TimeStampResp ::= SEQUENCE {
    //    status          PKIStatusInfo,
    //    timeStampToken  TimeStampToken  OPTIONAL
    // }

    final elements = ASN1Utils.parseSequence(response);
    if (elements.isEmpty) {
      throw FormatException('Invalid TimeStampResponse');
    }

    // Check status (should be granted = 0)
    // For now, just return the token if present
    if (elements.length >= 2) {
      // The second element is the TimeStampToken
      return elements[1].content;
    }

    throw FormatException('TimeStampResponse does not contain a token');
  }

  /// Generates a random nonce value.
  int _generateNonce() {
    return DateTime.now().microsecondsSinceEpoch;
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
class SimpleTSAClient extends TSAClientBouncyCastle {
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
