/// Helper class for internal usage only.
///  TODO ? Be aware that its API and functionality may be changed in future.
class StringUtil {
  StringUtil._();

  /// Replaces all occurrences of a pattern in a string.
  static String replaceAll(String srcString, String regex, String replacement) {
    return srcString.replaceAll(RegExp(regex), replacement);
  }

  /// Compiles a regular expression pattern.
  static RegExp regexCompile(String s,
      {bool caseSensitive = true, bool multiLine = false}) {
    return RegExp(s, caseSensitive: caseSensitive, multiLine: multiLine);
  }

  /// Splits the source string by the given sequence.
  /// If splitSequence is a single character, splits directly.
  /// Otherwise, treats splitSequence as a regex pattern.
  static List<String> split(String srcStr, String splitSequence) {
    if (splitSequence.length == 1) {
      return srcStr.trimRight().split(splitSequence);
    }
    return splitByRegex(RegExp(splitSequence), srcStr);
  }

  /// Splits the source string using a RegExp.
  static List<String> splitByRegex(RegExp regex, String srcStr) {
    final matches = regex.allMatches(srcStr);
    if (matches.isEmpty) {
      return [srcStr];
    }

    final result = <String>[];
    int prevEnd = 0;

    for (final match in matches) {
      if (match.start != 0 || prevEnd != 0) {
        final part = srcStr.substring(prevEnd, match.start);
        if (part.isNotEmpty || prevEnd == 0) {
          result.add(part);
        }
      }
      prevEnd = match.end;
    }

    if (prevEnd != srcStr.length) {
      result.add(srcStr.substring(prevEnd));
    }

    return result;
  }

  /// Checks if a string is null or empty.
  static bool isNullOrEmpty(String? s) {
    return s == null || s.isEmpty;
  }

  /// Checks if a string is null, empty, or contains only whitespace.
  static bool isNullOrWhitespace(String? s) {
    return s == null || s.trim().isEmpty;
  }

  /// Returns true if the string starts with the specified prefix.
  static bool startsWith(String str, String prefix) {
    return str.startsWith(prefix);
  }

  /// Returns true if the string ends with the specified suffix.
  static bool endsWith(String str, String suffix) {
    return str.endsWith(suffix);
  }
}
