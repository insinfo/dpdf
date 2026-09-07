import 'package:dpdf/src/styledxmlparser/css/common_css_constants.dart';
import 'package:dpdf/src/styledxmlparser/css/resolve/style_inheritance.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_dimension_parsing_utils.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_types_validation_utils.dart';

class CraftStyleUtil {
  CraftStyleUtil._();

  static final List<String> _fontSizeDependentPercentage = [
    CraftCommonCssConstants.FONT_SIZE,
    CraftCommonCssConstants.LINE_HEIGHT,
  ];

  static Map<String, String> mergeParentStyleDeclaration(
      Map<String, String> styles,
      String styleProperty,
      String parentPropValue,
      String parentFontSizeString,
      Iterable<CraftStyleInheritance> inheritanceRules) {
    String? childPropValue = styles[styleProperty];
    if ((childPropValue == null &&
            _checkInheritance(styleProperty, inheritanceRules)) ||
        "inherit" == childPropValue) {
      if (_valueIsOfMeasurement(parentPropValue, CraftCommonCssConstants.EM) ||
          _valueIsOfMeasurement(parentPropValue, CraftCommonCssConstants.EX) ||
          (_valueIsOfMeasurement(
                  parentPropValue, CraftCommonCssConstants.PERCENTAGE) &&
              _fontSizeDependentPercentage.contains(styleProperty))) {
        double absoluteParentFontSize =
            CraftCssDimensionParsingUtils.parseAbsoluteLength(
                parentFontSizeString);
        double relativeValue = CraftCssDimensionParsingUtils.parseRelativeValue(
            parentPropValue, absoluteParentFontSize);

        // Format to prevent differences.
        String formatted = relativeValue.toStringAsFixed(4);
        // Remove trailing zeros and dot if possible
        if (formatted.contains('.')) {
          formatted = formatted
              .replaceAll(RegExp(r'0+$'), '')
              .replaceAll(RegExp(r'\.+$'), '');
        }

        styles[styleProperty] = formatted + CraftCommonCssConstants.PT;
      } else {
        styles[styleProperty] = parentPropValue;
      }
    }
    return styles;
  }

  static bool _checkInheritance(
      String styleProperty, Iterable<CraftStyleInheritance> inheritanceRules) {
    for (var inheritanceRule in inheritanceRules) {
      if (inheritanceRule.isInheritable(styleProperty)) {
        return true;
      }
    }
    return false;
  }

  static bool _valueIsOfMeasurement(String? value, String measurement) {
    if (value == null) {
      return false;
    }
    return value.endsWith(measurement) &&
        CraftCssTypesValidationUtils.isNumber(
            value.substring(0, value.length - measurement.length).trim());
  }
}
