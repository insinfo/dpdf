/// Compression constants for PdfStream.
class CompressionConstants {
  CompressionConstants._();

  /// Undefined compression level.
  static const int undefinedCompression = -2147483648; // int.minValue

  /// Default compression level.
  static const int defaultCompression = -1;

  /// No compression.
  static const int noCompression = 0;

  /// Best speed compression.
  static const int bestSpeed = 1;

  /// Best compression level.
  static const int bestCompression = 9;
}
