import 'dart:typed_data';

/// Interface for message digest computation.
///
/// Used to abstract the actual digest implementation.
abstract class IMessageDigest {
  /// Updates the digest with more input bytes.
  void update(Uint8List input, [int offset = 0, int? length]);

  /// Completes the digest computation and returns the result.
  ///
  /// Resets the digest after returning.
  Uint8List digest();

  /// Returns the algorithm name.
  String getAlgorithmName();

  /// Returns the digest size in bytes.
  int getDigestSize();

  /// Resets the digest to its initial state.
  void reset();
}

/// ExternalDigest allows the use of implementations of [IMessageDigest]
/// other than the default BouncyCastle-based one.
abstract class IExternalDigest {
  /// Returns the MessageDigest associated with the provided hashing algorithm.
  ///
  /// @param hashAlgorithm String value representing the hashing algorithm
  /// @return MessageDigest object
  IMessageDigest getMessageDigest(String hashAlgorithm);
}
