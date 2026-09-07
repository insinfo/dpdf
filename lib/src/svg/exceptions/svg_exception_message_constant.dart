/// Diagnostic templates for DPDF. Public identifiers and format slots are stable.
class SvgExceptionMessageConstant {
  SvgExceptionMessageConstant._();

  static const String ARC_TO_EXPECTS_FOLLOWING_PARAMETERS_GOT_0 =
      'Elliptical-arc commands require groups of (rx ry rot largearc sweep x y); received {0}.';

  static const String
      COORDINATE_ARRAY_LENGTH_MUST_BY_DIVISIBLE_BY_CURRENT_COORDINATES_ARRAY_LENGTH =
      'Coordinate data must contain a whole number of groups matching the current coordinate group length.';

  static const String COULD_NOT_DETERMINE_MIDDLE_POINT_OF_ELLIPTICAL_ARC =
      'The elliptical arc does not yield a computable ellipse center.';

  static const String CURVE_TO_EXPECTS_FOLLOWING_PARAMETERS_GOT_0 =
      'Cubic-curve commands require groups of (x1 y1 x2 y2 x y); received {0}.';

  static const String DRAW_NO_DRAW =
      'This renderer does not provide a drawable representation.';

  static const String FAILED_TO_PARSE_INPUTSTREAM =
      'The SVG input stream could not be parsed.';

  static const String FONT_NOT_FOUND = 'No matching font could be resolved.';

  static const String I_NODE_ROOT_IS_NULL =
      'SVG processing requires a non-null input root node.';

  static const String MEET_OR_SLICE_ARGUMENT_IS_INCORRECT =
      'Use meet, slice, or null for the meetOrSlice argument.';

  static const String CURRENT_VIEWPORT_IS_NULL =
      'A current viewport is required before applying viewBox.';

  static const String VIEWBOX_IS_INCORRECT =
      'The viewBox definition is invalid and cannot be applied.';

  static const String INVALID_CLOSEPATH_OPERATOR_USE =
      'A path must begin with moveto (M) before closepath (Z) can be used.';

  static const String INVALID_PATH_D_ATTRIBUTE_OPERATORS =
      'The path d attribute contains unsupported operators: {0}.';

  static const String INVALID_SMOOTH_CURVE_USE =
      'Smooth-curve commands S, s, T, and t cannot start a path.';

  static const String INVALID_TRANSFORM_DECLARATION =
      'The transform declaration has invalid syntax.';

  static const String INVALID_TRANSFORM_VALUE =
      'The transform parameter value is invalid: {0}.';

  static const String LINE_TO_EXPECTS_FOLLOWING_PARAMETERS_GOT_0 =
      'Lineto commands require coordinate pairs (x y); received {0}.';

  static const String MOVE_TO_EXPECTS_FOLLOWING_PARAMETERS_GOT_0 =
      'Moveto commands require coordinate pairs (x y); received {0}.';

  static const String NAMED_OBJECT_NAME_NULL_OR_EMPTY =
      'A named object requires a non-null, nonempty name.';

  static const String NAMED_OBJECT_NULL =
      'The named-object value must be provided.';

  static const String NO_ROOT = 'The SVG input has no root element.';

  static const String PARAMETER_CANNOT_BE_NULL =
      'This operation requires non-null parameters.';

  static const String POINTS_ATTRIBUTE_INVALID_LIST =
      'Polyline points="{0}" is not a valid coordinate-pair list.';

  static const String QUADRATIC_CURVE_TO_EXPECTS_FOLLOWING_PARAMETERS_GOT_0 =
      'Quadratic-curve commands require groups of (x1 y1 x y); received {0}.';

  static const String ROOT_SVG_NO_BBOX =
      'Define a bounding box for the root SVG element before rendering.';

  static const String TAG_PARAMETER_NULL =
      'A non-null SVG tag argument is required.';

  static const String TRANSFORM_EMPTY =
      'Provide at least one transform value; the declaration is empty.';

  static const String TRANSFORM_INCORRECT_NUMBER_OF_VALUES =
      'The transform argument count does not match its operation.';

  static const String TRANSFORM_NULL =
      'A transform value is required but was null.';

  static const String UNKNOWN_TRANSFORMATION_TYPE =
      'The requested transform operation is not implemented.';

  static const String ILLEGAL_RELATIVE_VALUE_NO_VIEWPORT_IS_SET =
      'Set a viewport before resolving a relative SVG value.';
}
