import 'dart:typed_data';

/// Interface for decryption operations.
abstract class IDecryptor {
  /// Updates the decryptor with a chunk of data.
  ///
  /// [b] The data to decrypt.
  /// [off] The offset in the data array.
  /// [len] The length of the data to decrypt.
  ///
  /// Returns the decrypted data chunk.
  Uint8List? update(Uint8List b, int off, int len);

  /// Finishes the decryption process.
  ///
  /// Returns the final decrypted data chunk, or null if no data is left.
  Uint8List? finish();
}
