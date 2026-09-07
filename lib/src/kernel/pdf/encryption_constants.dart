/// Encryption constants for .
class EncryptionConstants {
  EncryptionConstants._();

  /// Selects RC4 with a 40-bit key.
  static const int standardEncryption40 = 0;

  /// Selects RC4 with a 128-bit key.
  static const int standardEncryption128 = 1;

  /// Selects AES with a 128-bit key.
  static const int encryptionAes128 = 2;

  /// Selects AES with a 256-bit key.
  static const int encryptionAes256 = 3;

  /// Type of encryption. Advanced Encryption Standard-Galois/Counter Mode (AES-GCM) encryption algorithm.
  static const int encryptionAesGcm = 4;

  /// Keeps document metadata outside encryption.
  static const int doNotEncryptMetadata = 8;

  /// Add this to the mode to encrypt only the embedded files.
  static const int embeddedFilesOnly = 24;

  /// The operation is permitted when the document is opened with the user password.
  static const int allowPrinting = 4 + 2048;

  /// The operation is permitted when the document is opened with the user password.
  static const int allowModifyContents = 8;

  /// The operation is permitted when the document is opened with the user password.
  static const int allowCopy = 16;

  /// The operation is permitted when the document is opened with the user password.
  static const int allowModifyAnnotations = 32;

  /// The operation is permitted when the document is opened with the user password.
  static const int allowFillIn = 256;

  /// The operation is permitted when the document is opened with the user password.
  static const int allowScreenreaders = 512;

  /// The operation is permitted when the document is opened with the user password.
  static const int allowAssembly = 1024;

  /// The operation is permitted when the document is opened with the user password.
  static const int allowDegradedPrinting = 4;

  /// Extracts the cipher selection from the combined options.
  static const int encryptionMask = 7;
}
