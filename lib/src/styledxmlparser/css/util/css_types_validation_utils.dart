import 'package:dpdf/src/styledxmlparser/css/common_css_constants.dart';

/// Utilities class for CSS types validating operations.
class CssTypesValidationUtils {
  CssTypesValidationUtils._();

  static const List<String> ANGLE_MEASUREMENTS_VALUES = [
    CommonCssConstants.DEG,
    CommonCssConstants.GRAD,
    CommonCssConstants.RAD
  ];

  static const List<String> RELATIVE_MEASUREMENTS_VALUES = [
    CommonCssConstants.PERCENTAGE,
    CommonCssConstants.EM,
    CommonCssConstants.EX,
    CommonCssConstants.REM
  ];

  static const List<String> METRIC_MEASUREMENTS_VALUES = [
    CommonCssConstants.PX,
    CommonCssConstants.IN,
    CommonCssConstants.CM,
    CommonCssConstants.MM,
    CommonCssConstants.PC,
    CommonCssConstants.PT,
    CommonCssConstants.Q
  ];

  /// Checks whether a string contains an allowed metric unit in HTML/CSS; rad, deg and grad.
  static bool isAngleValue(String? valueArgument) {
    if (valueArgument == null) return false;
    String value = valueArgument.trim();
    for (String metricPostfix in ANGLE_MEASUREMENTS_VALUES) {
      if (value.endsWith(metricPostfix) &&
          isNumber(value.substring(0, value.length - metricPostfix.length))) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether a string contains an allowed value relative to parent value.
  static bool isEmValue(String? valueArgument) {
    if (valueArgument == null) return false;
    String value = valueArgument.trim();
    return value.endsWith(CommonCssConstants.EM) &&
        isNumber(
            value.substring(0, value.length - CommonCssConstants.EM.length));
  }

  /// Checks whether a string contains an allowed value relative to element font height.
  static bool isExValue(String? valueArgument) {
    if (valueArgument == null) return false;
    String value = valueArgument.trim();
    return value.endsWith(CommonCssConstants.EX) &&
        isNumber(
            value.substring(0, value.length - CommonCssConstants.EX.length));
  }

  /// Checks whether a string contains an allowed metric unit in HTML/CSS; px, in, cm, mm, pc, Q or pt.
  static bool isMetricValue(String? valueArgument) {
    if (valueArgument == null) return false;
    String value = valueArgument.trim();
    for (String metricPostfix in METRIC_MEASUREMENTS_VALUES) {
      if (value.endsWith(metricPostfix) &&
          isNumber(value.substring(0, value.length - metricPostfix.length))) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether a string matches a numeric value (e.g. 123, 1.23, .123).
  static bool isNumber(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    return RegExp(r"^[-+]?\d*\.?\d+$").hasMatch(trimmed) ||
        RegExp(r"^[-+]?\d+\.?\d*$").hasMatch(trimmed);
  }

  /// Checks whether a string contains a percentage value
  static bool isPercentageValue(String? valueArgument) {
    if (valueArgument == null) return false;
    String value = valueArgument.trim();
    return value.endsWith(CommonCssConstants.PERCENTAGE) &&
        isNumber(value.substring(
            0, value.length - CommonCssConstants.PERCENTAGE.length));
  }

  /// Checks whether a string contains an allowed value relative to previously set value.
  static bool isRelativeValue(String? valueArgument) {
    if (valueArgument == null) return false;
    String value = valueArgument.trim();
    for (String relativePostfix in RELATIVE_MEASUREMENTS_VALUES) {
      if (value.endsWith(relativePostfix) &&
          isNumber(value.substring(0, value.length - relativePostfix.length))) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether a string contains an allowed value relative to previously set root value.
  static bool isRemValue(String? valueArgument) {
    if (valueArgument == null) return false;
    String value = valueArgument.trim();
    return value.endsWith(CommonCssConstants.REM) &&
        isNumber(
            value.substring(0, value.length - CommonCssConstants.REM.length));
  }

  static bool isNegativeValue(String? value) {
    if (value == null) return false;
    return value.trim().startsWith("-");
  }
}
