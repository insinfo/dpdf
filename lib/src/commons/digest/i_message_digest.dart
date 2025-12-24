import 'dart:typed_data';

/// This interface should be implemented to provide applications the functionality of a message digest algorithm.
abstract class IMessageDigest {
  /// Performs a final update on the digest using the specified array of bytes,
  /// then completes the digest computation.
  ///
  /// [enc] The input to be updated before the digest is completed.
  ///
  /// Returns the array of bytes for the resulting hash value.
  Uint8List digestWithInput(Uint8List enc);

  /// Completes the hash computation by performing final operations such as padding.
  /// Leaves the digest reset.
  ///
  /// Returns the array of bytes for the resulting hash value.
  Uint8List digest();

  /// Gets byte length of wrapped digest algorithm.
  ///
  /// Returns the length of the digest in bytes.
  int getDigestLength();

  /// Updates the digest using the specified array of bytes, starting at the specified offset.
  ///
  /// [buf] Byte array buffer.
  /// [off] The offset to start from in the array of bytes.
  /// [len] The number of bytes to use, starting at offset.
  void update(Uint8List buf, int off, int len);

  /// Updates the digest using the specified array of bytes.
  ///
  /// [buf] Byte array buffer.
  void updateAll(Uint8List buf);

  /// Resets the digest for further use.
  void reset();

  /// Returns a string that identifies the algorithm, independent of implementation details.
  ///
  /// Returns the name of the algorithm.
  String getAlgorithmName();
}
