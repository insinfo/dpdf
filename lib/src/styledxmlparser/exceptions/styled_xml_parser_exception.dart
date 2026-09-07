class StyledXMLParserException implements Exception {
  static const String INVALID_GRADIENT_FUNCTION_ARGUMENTS_LIST =
      "Cannot interpret these gradient arguments: {0}";
  static const String INVALID_GRADIENT_TO_SIDE_OR_CORNER_STRING =
      "The gradient direction is not recognized: {0}";
  static const String INVALID_GRADIENT_COLOR_STOP_VALUE =
      "Cannot interpret this gradient stop: {0}";
  static const String NAN = "A numeric CSS value was expected at @{0}.";
  static const String FontProviderContainsZeroFonts =
      "Rendering requires a font, but the provider has none registered.";
  static const String UnsupportedEncodingException =
      "The requested text encoding has no available implementation.";

  final String message;
  StyledXMLParserException(this.message);

  @override
  String toString() => 'StyledXMLParserException: $message';
}
