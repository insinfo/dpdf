import 'dart:typed_data';
import 'certificate_details.dart';

/// Retrieves certificate status using OCSP.
abstract class OcspClient {
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
  ///            look for an endpoint in the AuthorityInformationAccess extension of
  ///            the certificate, or from another implementation-specific source.
  /// @return encoded BasicOCSPResponse, or null when a response
  ///         could not be obtained
  /// @see https://datatracker.ietf.org/doc/html/rfc6960#section-4.2.1
  Future<Uint8List?> getEncoded(
      CertificateDetails checkCert, CertificateDetails issuerCert, String? url);
}
