/// Stream compression levels, shared by [CraftPdfStream] and the writer.
///
/// The values are the zlib levels, so they can be passed straight to the
/// deflate implementation.
class CraftCompressionConstants {
  CraftCompressionConstants._();

  /// No level was chosen, so the caller's default applies.
  ///
  /// This is the same value as [defaultCompression] because zlib itself uses
  /// -1 to mean "the implementation decides"; the two names record intent, not
  /// different behaviour.
  static const int undefinedCompression = -1;

  /// Let the deflate implementation choose, which is level 6 in zlib.
  static const int defaultCompression = -1;

  /// Store the data without compressing it.
  static const int noCompression = 0;

  /// Compress as fast as possible.
  static const int bestSpeed = 1;

  /// Compress as small as possible.
  static const int bestCompression = 9;
}
