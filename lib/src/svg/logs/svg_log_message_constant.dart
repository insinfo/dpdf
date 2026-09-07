/// Diagnostic templates for DPDF. Public identifiers and format slots are stable.
class SvgLogMessageConstant {
  SvgLogMessageConstant._();

  static const String CUSTOM_ABSTRACT_CSS_CONTEXT_NOT_SUPPORTED =
      'This renderer does not accept custom AbstractCssContext implementations.';

  static const String ERROR_INITIALIZING_DEFAULT_CSS =
      'Default CSS could not be loaded; continuing with an empty stylesheet.';

  static const String GRADIENT_INVALID_GRADIENT_UNITS_LOG =
      'Unrecognized gradientUnits setting: {0}.';

  static const String GRADIENT_INVALID_SPREAD_METHOD_LOG =
      'Unrecognized gradient spreadMethod setting: {0}.';

  static const String MARKER_HEIGHT_IS_NEGATIVE_VALUE =
      'Skipping the marker because markerHeight is below zero.';

  static const String MARKER_HEIGHT_IS_ZERO_VALUE =
      'Skipping the marker because markerHeight is zero.';

  static const String MARKER_WIDTH_IS_NEGATIVE_VALUE =
      'Skipping the marker because markerWidth is below zero.';

  static const String MARKER_WIDTH_IS_ZERO_VALUE =
      'Skipping the marker because markerWidth is zero.';

  static const String PATTERN_INVALID_PATTERN_UNITS_LOG =
      'Unrecognized patternUnits setting: {0}.';

  static const String PATTERN_INVALID_PATTERN_CONTENT_UNITS_LOG =
      'Unrecognized patternContentUnits setting: {0}.';

  static const String PATTERN_WIDTH_OR_HEIGHT_IS_ZERO =
      'Skipping the pattern because its width or height is zero.';

  static const String PATTERN_WIDTH_OR_HEIGHT_IS_NEGATIVE =
      'Skipping the pattern because its width or height is below zero.';

  @deprecated
  static const String MISSING_WIDTH =
      'The root SVG specifies neither a width nor a viewBox width; using the browser fallback of 300px.';

  @deprecated
  static const String MISSING_HEIGHT =
      'The root SVG specifies neither a height nor a viewBox height; using the browser fallback of 150px.';

  static const String NONINVERTIBLE_TRANSFORMATION_MATRIX_USED_IN_CLIP_PATH =
      'The clipping transform is singular; rendering clipped elements may be unreliable.';

  static const String
      NON_INVERTIBLE_TRANSFORMATION_MATRIX_FOR_NON_SCALING_STROKE =
      'Cannot apply non-scaling-stroke: a document transform has zero determinant and cannot be inverted.';

  static const String UNABLE_TO_GET_INVERSE_MATRIX_DUE_TO_ZERO_DETERMINANT =
      'A document transform has zero determinant, preventing viewport calculation; using a zero-sized bounding box as the element viewport.';

  static const String UNABLE_TO_RETRIEVE_FONT = 'Font retrieval failed: {0}.';

  static const String VIEWBOX_VALUE_MUST_BE_FOUR_NUMBERS =
      'Ignoring viewBox="{0}": exactly four numeric values are required.';

  static const String VIEWBOX_WIDTH_AND_HEIGHT_CANNOT_BE_NEGATIVE =
      'Ignoring viewBox="{0}": width and height must be nonnegative.';

  static const String VIEWBOX_WIDTH_OR_HEIGHT_IS_ZERO =
      'Skipping the element because its viewBox has zero width or height.';

  static const String UNMAPPED_TAG =
      'No renderer is registered for SVG tag {0}.';
}
