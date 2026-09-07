import 'package:dpdf/src/styledxmlparser/css/common_css_constants.dart';

/// Utilities class for CSS types validating operations.
class CraftCssTypesValidationUtils {
  CraftCssTypesValidationUtils._();

  static const List<String> ANGLE_MEASUREMENTS_VALUES = [
    CraftCommonCssConstants.DEG,
    CraftCommonCssConstants.GRAD,
    CraftCommonCssConstants.RAD
  ];

  static const List<String> RELATIVE_MEASUREMENTS_VALUES = [
    CraftCommonCssConstants.PERCENTAGE,
    CraftCommonCssConstants.EM,
    CraftCommonCssConstants.EX,
    CraftCommonCssConstants.REM
  ];

  static const List<String> METRIC_MEASUREMENTS_VALUES = [
    CraftCommonCssConstants.PX,
    CraftCommonCssConstants.IN,
    CraftCommonCssConstants.CM,
    CraftCommonCssConstants.MM,
    CraftCommonCssConstants.PC,
    CraftCommonCssConstants.PT,
    CraftCommonCssConstants.Q
  ];

  /// Recognizes angular CSS units: rad, deg and grad.
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

  /// Recognizes values expressed relative to the parent.
  static bool isEmValue(String? valueArgument) {
    if (valueArgument == null) return false;
    String value = valueArgument.trim();
    return value.endsWith(CraftCommonCssConstants.EM) &&
        isNumber(value.substring(
            0, value.length - CraftCommonCssConstants.EM.length));
  }

  /// Recognizes values relative to the element's font height.
  static bool isExValue(String? valueArgument) {
    if (valueArgument == null) return false;
    String value = valueArgument.trim();
    return value.endsWith(CraftCommonCssConstants.EX) &&
        isNumber(value.substring(
            0, value.length - CraftCommonCssConstants.EX.length));
  }

  /// Recognizes absolute CSS lengths: px, in, cm, mm, pc, Q and pt.
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
    return value.endsWith(CraftCommonCssConstants.PERCENTAGE) &&
        isNumber(value.substring(
            0, value.length - CraftCommonCssConstants.PERCENTAGE.length));
  }

  /// Recognizes values relative to the previous value.
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

  /// Recognizes values relative to the root's previous value.
  static bool isRemValue(String? valueArgument) {
    if (valueArgument == null) return false;
    String value = valueArgument.trim();
    return value.endsWith(CraftCommonCssConstants.REM) &&
        isNumber(value.substring(
            0, value.length - CraftCommonCssConstants.REM.length));
  }

  static bool isNegativeValue(String? value) {
    if (value == null) return false;
    return value.trim().startsWith("-");
  }
}
