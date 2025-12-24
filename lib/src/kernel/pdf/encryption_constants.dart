/// Encryption constants for PDF documents.
///
/// Used in [WriterProperties.setStandardEncryption] to specify
/// the type of encryption and permissions.
class EncryptionConstants {
  EncryptionConstants._();

  // Encryption types

  /// RC4 encryption with 40-bit key.
  static const int standardEncryption40 = 0;

  /// RC4 encryption with 128-bit key.
  static const int standardEncryption128 = 1;

  /// AES encryption with 128-bit key.
  static const int encryptionAes128 = 2;

  /// AES encryption with 256-bit key.
  static const int encryptionAes256 = 3;

  /// AES-GCM encryption (Advanced Encryption Standard-Galois/Counter Mode).
  static const int encryptionAesGcm = 4;

  /// Add to mode to keep metadata in clear text.
  static const int doNotEncryptMetadata = 8;

  /// Add to mode to encrypt only embedded files.
  static const int embeddedFilesOnly = 24;

  // Permissions

  /// Permit printing.
  static const int allowPrinting = 4 + 2048;

  /// Permit modifying contents.
  static const int allowModifyContents = 8;

  /// Permit copying.
  static const int allowCopy = 16;

  /// Permit modifying annotations.
  static const int allowModifyAnnotations = 32;

  /// Permit filling in form fields.
  static const int allowFillIn = 256;

  /// Permit screen readers to read content.
  static const int allowScreenreaders = 512;

  /// Permit document assembly.
  static const int allowAssembly = 1024;

  /// Permit degraded printing.
  static const int allowDegradedPrinting = 4;

  /// Mask to separate encryption type from mode.
  static const int encryptionMask = 7;
}
