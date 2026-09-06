import 'dart:typed_data';

import 'signature_mechanism_params.dart';

/// Contract for an external signing operation.
///
/// Implementations may, for example, need
/// to sign a PDF using a smart card.
abstract class CraftExternalSignature {
  /// Returns the digest algorithm.
  ///
  /// @return The digest algorithm (e.g. "SHA-1", "SHA-256",...).
  String getDigestAlgorithmName();

  /// Returns the signature algorithm used for signing, disregarding the
  /// digest function.
  ///
  /// @return signing algorithm name
  String getSignatureAlgorithmName();

  /// Return the algorithm parameters that need to be encoded together with the
  /// signature mechanism identifier.
  ///
  /// If there are no parameters, return `null`.
  /// A non-null value is required for RSASSA-PSS.
  ///
  /// @return algorithm parameters or null
  CraftSignatureMechanismParams? getSignatureMechanismParameters();

  /// Combines the configured signing and digest algorithms to sign
  /// with the hash algorithm.
  ///
  /// @param message input bytes to hash and sign
  /// @return A signed message digest.
  Future<Uint8List> sign(Uint8List message);
}
