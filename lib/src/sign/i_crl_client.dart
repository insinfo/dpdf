import 'dart:typed_data';
import 'i_x509_certificate.dart';

/// Interface that needs to be implemented if you want to embed
/// Certificate Revocation Lists (CRL) into your PDF.
abstract class ICrlClient {
  /// Gets an encoded byte array.
  ///
  /// @param checkCert The certificate which a CRL URL can be obtained from (as bytes).
  /// @param url A CRL url if you don't want to obtain it from the certificate.
  /// @return A collection of byte arrays each representing a CRL.
  ///         It may return null or an empty collection.
  Future<List<Uint8List>?> getEncoded(IX509Certificate? checkCert, String? url);
}
