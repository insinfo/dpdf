import 'dart:typed_data';

/// Interface for the Online Certificate Status Protocol (OCSP) Client.
abstract class IOcspClient {
  /// Fetch a DER-encoded BasicOCSPResponse from an OCSP responder.
  ///
  /// The method should not throw an exception.
  ///
  /// Note: do not pass in the full DER-encoded OCSPResponse object obtained
  /// from the responder, only the DER-encoded BasicOCSPResponse value
  /// contained in the response data.
  ///
  /// @param checkCert Certificate to check (as bytes).
  /// @param issuerCert The parent certificate (as bytes).
  /// @param url The URL of the OCSP responder endpoint. If null, implementations can
  ///            attempt to obtain a URL from the AuthorityInformationAccess extension of
  ///            the certificate, or from another implementation-specific source.
  /// @return a byte array containing a DER-encoded BasicOCSPResponse structure or null if one
  ///         could not be obtained
  /// @see https://datatracker.ietf.org/doc/html/rfc6960#section-4.2.1
  Future<Uint8List?> getEncoded(
      Uint8List checkCert, Uint8List issuerCert, String? url);
}
