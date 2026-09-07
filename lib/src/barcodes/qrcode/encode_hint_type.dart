/// These are a set of hints that you may pass to Writers to specify their behavior.
enum EncodeHintType {
  /// Specifies what degree of error correction to use, for example in QR Codes (type Integer).
  ERROR_CORRECTION,

  /// Specifies what character encoding to use where applicable (type String)
  CHARACTER_SET,

  /// Specifies the minimal version level to use, for example in QR Codes (type Integer).
  MIN_VERSION_NR
}
