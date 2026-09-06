/// Class that holds the logging and exception messages.
class SvgLogMessageConstant {
  SvgLogMessageConstant._();

  static const String CUSTOM_ABSTRACT_CSS_CONTEXT_NOT_SUPPORTED =
      "Custom AbstractCssContext implementations are not supported yet";

  static const String ERROR_INITIALIZING_DEFAULT_CSS =
      "Error loading the default CSS. Initializing an empty style sheet.";

  static const String GRADIENT_INVALID_GRADIENT_UNITS_LOG =
      "Could not recognize gradient units value {0}";

  static const String GRADIENT_INVALID_SPREAD_METHOD_LOG =
      "Could not recognize gradient spread method value {0}";

  static const String MARKER_HEIGHT_IS_NEGATIVE_VALUE =
      "markerHeight has negative value. Marker will not be rendered.";

  static const String MARKER_HEIGHT_IS_ZERO_VALUE =
      "markerHeight has zero value. Marker will not be rendered.";

  static const String MARKER_WIDTH_IS_NEGATIVE_VALUE =
      "markerWidth has negative value. Marker will not be rendered.";

  static const String MARKER_WIDTH_IS_ZERO_VALUE =
      "markerWidth has zero value. Marker will not be rendered.";

  static const String PATTERN_INVALID_PATTERN_UNITS_LOG =
      "Could not recognize patternUnits value {0}";

  static const String PATTERN_INVALID_PATTERN_CONTENT_UNITS_LOG =
      "Could not recognize patternContentUnits value {0}";

  static const String PATTERN_WIDTH_OR_HEIGHT_IS_ZERO =
      "Pattern width or height is zero. This pattern will not be rendered.";

  static const String PATTERN_WIDTH_OR_HEIGHT_IS_NEGATIVE =
      "Pattern width or height is negative value. This pattern will not be rendered.";

  @deprecated
  static const String MISSING_WIDTH =
      "Top Svg tag has no defined width attribute and viewbox width is not present, so browser default of 300px is used";

  @deprecated
  static const String MISSING_HEIGHT =
      "Top Svg tag has no defined height attribute and viewbox height is not present, so browser default of 150px is used";

  static const String NONINVERTIBLE_TRANSFORMATION_MATRIX_USED_IN_CLIP_PATH =
      "Non-invertible transformation matrix was used in a clipping path context. Clipped elements may show undefined behavior.";

  static const String
      NON_INVERTIBLE_TRANSFORMATION_MATRIX_FOR_NON_SCALING_STROKE =
      "Unable to get inverse transformation matrix and thus apply non-scaling-stroke vector-effect property: some of the transformation matrices, written to the document, have a determinant of zero value.";

  static const String UNABLE_TO_GET_INVERSE_MATRIX_DUE_TO_ZERO_DETERMINANT =
      "Unable to get inverse transformation matrix and thus calculate a viewport for the element because some of the transformation matrices, which are written to document, have a determinant of zero value. A bbox of zero values will be used as a viewport for this element.";

  static const String UNABLE_TO_RETRIEVE_FONT =
      "Unable to retrieve font:\n {0}";

  static const String VIEWBOX_VALUE_MUST_BE_FOUR_NUMBERS =
      "The viewBox value must be 4 numbers. This viewBox=\"{0}\" will not be processed.";

  static const String VIEWBOX_WIDTH_AND_HEIGHT_CANNOT_BE_NEGATIVE =
      "The viewBox width and height cannot be negative. This viewBox=\"{0}\" will not be processed.";

  static const String VIEWBOX_WIDTH_OR_HEIGHT_IS_ZERO =
      "The viewBox width or height is zero. The element with this viewBox will not be rendered.";

  static const String UNMAPPED_TAG =
      "Could not find implementation for tag {0}";
}
