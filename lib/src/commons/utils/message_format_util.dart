/// Helper class for internal usage only.

class MessageFormatUtil {
  MessageFormatUtil._();

  /// Formats a pattern string with the provided arguments.
  ///
  /// The pattern should contain placeholders like `{0}`, `{1}`, etc.
  /// which will be replaced by the corresponding arguments.
  ///
  /// Example:
  /// ```dart
  /// MessageFormatUtil.format('Hello {0}, you have {1} messages.', ['John', 5]);
  /// // Returns: 'Hello John, you have 5 messages.'
  /// ```
  static String format(String pattern, List<Object?> arguments) {
    var result = pattern;
    for (int i = 0; i < arguments.length; i++) {
      result = result.replaceAll('{$i}', arguments[i]?.toString() ?? 'null');
    }
    return result;
  }
}
