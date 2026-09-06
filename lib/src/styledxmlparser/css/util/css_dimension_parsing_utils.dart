import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/styledxmlparser/css/common_css_constants.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_types_validation_utils.dart';
import 'package:dpdf/src/styledxmlparser/exceptions/styled_xml_parser_exception.dart';

/// Utilities class for CSS dimension parsing operations.
class CssDimensionParsingUtils {
  CssDimensionParsingUtils._();

  /// Parses a float without throwing an exception if something goes wrong.
  static double? parseFloat(String? str) {
    if (str == null) return null;
    return double.tryParse(str);
  }

  /// Parses a length with an allowed metric unit (px, pt, in, cm, mm, pc, q) or numeric value (e.g. 123, 1.23, .123) to pt.
  static double parseAbsoluteLength(String length,
      [String defaultMetric = CommonCssConstants.PX]) {
    int pos = determinePositionBetweenValueAndUnit(length);
    if (pos == 0) {
      throw StyledXMLParserException(
          StyledXMLParserException.NAN.replaceFirst("{0}", length));
    }
    double f = double.parse(length.substring(0, pos));
    String unit = length.substring(pos);

    if (unit.startsWith(CommonCssConstants.PT) ||
        (unit == "" && defaultMetric == CommonCssConstants.PT)) {
      return f;
    }
    if (unit.startsWith(CommonCssConstants.IN) ||
        (unit == "" && defaultMetric == CommonCssConstants.IN)) {
      return f * 72;
    }
    if (unit.startsWith(CommonCssConstants.CM) ||
        (unit == "" && defaultMetric == CommonCssConstants.CM)) {
      return (f / 2.54) * 72;
    }
    if (unit.startsWith(CommonCssConstants.Q) ||
        (unit == "" && defaultMetric == CommonCssConstants.Q)) {
      return (f / 2.54) * 72 / 40;
    }
    if (unit.startsWith(CommonCssConstants.MM) ||
        (unit == "" && defaultMetric == CommonCssConstants.MM)) {
      return (f / 25.4) * 72;
    }
    if (unit.startsWith(CommonCssConstants.PC) ||
        (unit == "" && defaultMetric == CommonCssConstants.PC)) {
      return f * 12;
    }
    if (unit.startsWith(CommonCssConstants.PX) ||
        (unit == "" && defaultMetric == CommonCssConstants.PX)) {
      return f * 0.75;
    }
    return f;
  }

  /// Parses an relative value based on the base value that was given, in the metric unit of the base value.
  static double parseRelativeValue(String relativeValue, double baseValue) {
    int pos = determinePositionBetweenValueAndUnit(relativeValue);
    if (pos == 0) return 0.0;
    double f = double.parse(relativeValue.substring(0, pos));
    String unit = relativeValue.substring(pos);

    if (unit.startsWith(CommonCssConstants.PERCENTAGE)) {
      return baseValue * f / 100;
    } else if (unit.startsWith(CommonCssConstants.EM) ||
        unit.startsWith(CommonCssConstants.REM)) {
      return baseValue * f;
    } else if (unit.startsWith(CommonCssConstants.EX)) {
      return baseValue * f / 2;
    }
    return f;
  }

  /// Convenience method for parsing a value to pt.
  static UnitValue? parseLengthValueToPt(
      String? value, double emValue, double remValue) {
    if (value == null) return null;
    if (CssTypesValidationUtils.isMetricValue(value) ||
        CssTypesValidationUtils.isNumber(value)) {
      return UnitValue(UnitValue.POINT, parseAbsoluteLength(value));
    } else if (value.endsWith(CommonCssConstants.PERCENTAGE)) {
      return UnitValue(UnitValue.PERCENT,
          double.parse(value.substring(0, value.length - 1)));
    } else if (CssTypesValidationUtils.isRemValue(value)) {
      return UnitValue(UnitValue.POINT, parseRelativeValue(value, remValue));
    } else if (CssTypesValidationUtils.isRelativeValue(value)) {
      return UnitValue(UnitValue.POINT, parseRelativeValue(value, emValue));
    }
    return null;
  }

  /// Parse length attributes.
  static double parseLength(String length, double percentBaseValue,
      double defaultValue, double fontSize, double rootFontSize) {
    if (CssTypesValidationUtils.isPercentageValue(length)) {
      return parseRelativeValue(length, percentBaseValue);
    } else {
      UnitValue? unitValue =
          parseLengthValueToPt(length, fontSize, rootFontSize);
      if (unitValue != null && unitValue.isPointValue()) {
        return unitValue.getValue();
      } else {
        return defaultValue;
      }
    }
  }

  /// Determines the position between digits and affiliated characters and all other characters.
  static int determinePositionBetweenValueAndUnit(String? string) {
    if (string == null) return 0;
    int pos = 0;
    while (pos < string.length) {
      var char = string[pos];
      if (char == '+' ||
          char == '-' ||
          char == '.' ||
          _isDigit(char) ||
          _isExponentNotation(string, pos)) {
        pos++;
      } else {
        break;
      }
    }
    return pos;
  }

  static bool _isDigit(String char) {
    return char.compareTo('0') >= 0 && char.compareTo('9') <= 0;
  }

  static bool _isExponentNotation(String s, int index) {
    if (index >= s.length) return false;
    var char = s[index].toLowerCase();
    if (char == 'e') {
      if (index + 1 < s.length && _isDigit(s[index + 1])) return true;
      if (index + 2 < s.length &&
          (s[index + 1] == '-' || s[index + 1] == '+') &&
          _isDigit(s[index + 2])) return true;
    }
    return false;
  }

  static double parseAbsoluteFontSize(String? fontSizeAttribute) {
    if (fontSizeAttribute == null) return 12.0;
    // Map keywords
    if (CommonCssConstants.FONT_ABSOLUTE_SIZE_KEYWORDS_VALUES
        .containsKey(fontSizeAttribute)) {
      return parseAbsoluteLength(CommonCssConstants
          .FONT_ABSOLUTE_SIZE_KEYWORDS_VALUES[fontSizeAttribute]!);
    }
    return parseAbsoluteLength(fontSizeAttribute);
  }

  static double parseRelativeFontSize(
      String elementFontSize, double baseFontSize) {
    if (elementFontSize == CommonCssConstants.LARGER) {
      return baseFontSize * 1.2;
    } else if (elementFontSize == CommonCssConstants.SMALLER) {
      return baseFontSize / 1.2;
    }
    return parseRelativeValue(elementFontSize, baseFontSize);
  }
}
