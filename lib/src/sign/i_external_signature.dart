import 'dart:typed_data';

import 'i_signature_mechanism_params.dart';

/// Interface that needs to be implemented to do the actual signing.
///
/// For instance: you'll have to implement this interface if you want
/// to sign a PDF using a smart card.
abstract class IExternalSignature {
  /// Returns the digest algorithm.
  ///
  /// @return The digest algorithm (e.g. "SHA-1", "SHA-256",...).
  String getDigestAlgorithmName();

  /// Returns the signature algorithm used for signing, disregarding the
  /// digest function.
  ///
  /// @return The signature algorithm ("RSA", "DSA", "ECDSA", "Ed25519" or "Ed448").
  String getSignatureAlgorithmName();

  /// Return the algorithm parameters that need to be encoded together with the
  /// signature mechanism identifier.
  ///
  /// If there are no parameters, return `null`.
  /// A non-null value is required for RSASSA-PSS.
  ///
  /// @return algorithm parameters or null
  ISignatureMechanismParams? getSignatureMechanismParameters();

  /// Signs the given message using the encryption algorithm in combination
  /// with the hash algorithm.
  ///
  /// @param message The message you want to be hashed and signed.
  /// @return A signed message digest.
  Future<Uint8List> sign(Uint8List message);
}
