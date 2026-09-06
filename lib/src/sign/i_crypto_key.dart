import 'dart:typed_data';

/// Interface for a private key.
///
/// This abstracts the private key to allow different crypto implementations.
abstract class IPrivateKey {
  /// Gets the algorithm name (e.g., "RSA", "ECDSA", "Ed25519").
  String getAlgorithm();

  /// Gets the key format (e.g., "PKCS#8").
  String getFormat();

  /// Gets the encoded key bytes.
  ///
  /// @return the encoded key, or null if encoding is not supported
  Uint8List? getEncoded();
}

/// Interface for a public key.
abstract class IPublicKey {
  /// Gets the algorithm name.
  String getAlgorithm();

  /// Gets the key format.
  String getFormat();

  /// Gets the encoded key bytes.
  Uint8List? getEncoded();
}

/// Interface for a signature algorithm.
abstract class ISigner {
  /// Initializes the signer for signing with a private key.
  void initSign(IPrivateKey privateKey);

  /// Initializes the signer for verification with a public key.
  void initVerify(IPublicKey publicKey);

  /// Updates the data to be signed/verified.
  void update(Uint8List data, [int offset = 0, int? length]);

  /// Generates the signature.
  ///
  /// @return the signature bytes
  Uint8List generateSignature();

  /// Verifies a signature.
  ///
  /// @param signature the signature to verify
  /// @return true if the signature is valid
  bool verify(Uint8List signature);
}
