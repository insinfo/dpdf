/// Class that bundles all the error message templates as constants.
class SvgExceptionMessageConstant {
  SvgExceptionMessageConstant._();

  static const String ARC_TO_EXPECTS_FOLLOWING_PARAMETERS_GOT_0 =
      "(rx ry rot largearc sweep x y)+ parameters are expected for elliptical arcs. Got: {0}";

  static const String
      COORDINATE_ARRAY_LENGTH_MUST_BY_DIVISIBLE_BY_CURRENT_COORDINATES_ARRAY_LENGTH =
      "Array of current coordinates must have length that is divisible by the length of the array with current coordinates";

  static const String COULD_NOT_DETERMINE_MIDDLE_POINT_OF_ELLIPTICAL_ARC =
      "Could not determine the middle point of the ellipse traced by this elliptical arc";

  static const String CURVE_TO_EXPECTS_FOLLOWING_PARAMETERS_GOT_0 =
      "(x1 y1 x2 y2 x y)+ parameters are expected for curves. Got: {0}";

  static const String DRAW_NO_DRAW = "The renderer cannot be drawn.";

  static const String FAILED_TO_PARSE_INPUTSTREAM =
      "Failed to parse InputStream.";

  static const String FONT_NOT_FOUND = "The font wasn't found.";

  static const String I_NODE_ROOT_IS_NULL = "Input root value is null";

  static const String MEET_OR_SLICE_ARGUMENT_IS_INCORRECT =
      "The meetOrSlice argument is incorrect. It must be `meet`, `slice` or null.";

  static const String CURRENT_VIEWPORT_IS_NULL =
      "The current viewport is null. The viewBox applying could not be processed.";

  static const String VIEWBOX_IS_INCORRECT =
      "The viewBox is incorrect. The viewBox applying could not be processed.";

  static const String INVALID_CLOSEPATH_OPERATOR_USE =
      "The close path operator (Z) may not be used before a move to operation (M)";

  static const String INVALID_PATH_D_ATTRIBUTE_OPERATORS =
      "Invalid operators found in path data attribute: {0}";

  static const String INVALID_SMOOTH_CURVE_USE =
      "The smooth curve operations (S, s, T, t) may not be used as a first operator in path.";

  static const String INVALID_TRANSFORM_DECLARATION =
      "Transformation declaration is not formed correctly.";

  static const String INVALID_TRANSFORM_VALUE =
      "Invalid transformation value: {0}";

  static const String LINE_TO_EXPECTS_FOLLOWING_PARAMETERS_GOT_0 =
      "(x y)+ parameters are expected for lineTo operator. Got: {0}";

  static const String MOVE_TO_EXPECTS_FOLLOWING_PARAMETERS_GOT_0 =
      "(x y)+ parameters are expected for moveTo operator. Got: {0}";

  static const String NAMED_OBJECT_NAME_NULL_OR_EMPTY =
      "The name of the named object can't be null or empty.";

  static const String NAMED_OBJECT_NULL = "A named object can't be null.";

  static const String NO_ROOT = "No root found";

  static const String PARAMETER_CANNOT_BE_NULL = "Parameters cannot be null.";

  static const String POINTS_ATTRIBUTE_INVALID_LIST =
      "Points attribute {0} on polyline tag does not contain a valid set of points";

  static const String QUADRATIC_CURVE_TO_EXPECTS_FOLLOWING_PARAMETERS_GOT_0 =
      "(x1 y1 x y)+ parameters are expected for quadratic curves. Got: {0}";

  static const String ROOT_SVG_NO_BBOX =
      "The root svg tag needs to have a bounding box defined.";

  static const String TAG_PARAMETER_NULL = "Tag parameter must not be null";

  static const String TRANSFORM_EMPTY = "The transformation value is empty.";

  static const String TRANSFORM_INCORRECT_NUMBER_OF_VALUES =
      "Transformation doesn't contain the right number of values.";

  static const String TRANSFORM_NULL = "The transformation value is null.";

  static const String UNKNOWN_TRANSFORMATION_TYPE =
      "Unsupported type of transformation.";

  static const String ILLEGAL_RELATIVE_VALUE_NO_VIEWPORT_IS_SET =
      "Relative value can't be resolved, no viewport is set.";
}
