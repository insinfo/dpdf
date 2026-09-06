class StyledXMLParserException implements Exception {
  static const String INVALID_GRADIENT_FUNCTION_ARGUMENTS_LIST =
      "Invalid gradient function arguments list: {0}";
  static const String INVALID_GRADIENT_TO_SIDE_OR_CORNER_STRING =
      "Invalid direction string: {0}";
  static const String INVALID_GRADIENT_COLOR_STOP_VALUE =
      "Invalid color stop value: {0}";
  static const String NAN = "The passed value (@{0}) is not a number";
  static const String FontProviderContainsZeroFonts =
      "Font Provider contains zero fonts. At least one font shall be present";
  static const String UnsupportedEncodingException =
      "Unsupported encoding exception.";

  final String message;
  StyledXMLParserException(this.message);

  @override
  String toString() => 'StyledXMLParserException: $message';
}
