/// Decodes a scalar from a UTF-16BE mapping source without silently truncating
/// multi-character strings or incomplete byte pairs.
int unicodeMappingScalar(String source) {
  final bytes = source.codeUnits;
  if ((bytes.length != 2 && bytes.length != 4) || bytes.any((v) => v > 255)) {
    throw FormatException(
        'Unicode mapping source must encode exactly one scalar.');
  }
  final first = bytes[0] * 256 + bytes[1];
  if (bytes.length == 2 && (first < 0xd800 || first > 0xdfff)) return first;
  if (bytes.length == 4 && first >= 0xd800 && first <= 0xdbff) {
    final second = bytes[2] * 256 + bytes[3];
    if (second >= 0xdc00 && second <= 0xdfff) {
      return 0x10000 + (first - 0xd800) * 1024 + second - 0xdc00;
    }
  }
  throw FormatException(
      'Unicode mapping source has invalid surrogate structure.');
}
