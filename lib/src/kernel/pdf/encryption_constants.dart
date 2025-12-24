/// Encryption constants for iText.
class EncryptionConstants {
  EncryptionConstants._();

  /// Type of encryption. RC4 encryption algorithm will be used with the key length of 40 bits.
  static const int standardEncryption40 = 0;

  /// Type of encryption. RC4 encryption algorithm will be used with the key length of 128 bits.
  static const int standardEncryption128 = 1;

  /// Type of encryption. AES encryption algorithm will be used with the key length of 128 bits.
  static const int encryptionAes128 = 2;

  /// Type of encryption. AES encryption algorithm will be used with the key length of 256 bits.
  static const int encryptionAes256 = 3;

  /// Type of encryption. Advanced Encryption Standard-Galois/Counter Mode (AES-GCM) encryption algorithm.
  static const int encryptionAesGcm = 4;

  /// Add this to the mode to keep the metadata in clear text.
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

  /// Mask to separate the encryption type from the encryption mode.
  static const int encryptionMask = 7;
}
