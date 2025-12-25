import 'dart:typed_data';

/// Interface to encode the parameters to a signature algorithm for inclusion
/// in a signature object.
///
/// See [RSASSAPSSMechanismParams] for an example.
abstract class ISignatureMechanismParams {
  /// Represent the parameters as an ASN.1 encodable for inclusion in a
  /// signature object.
  Uint8List toEncodable();
}
