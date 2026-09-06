import 'package:pdfcraft/src/layout/properties/unit_value.dart';
import 'package:pdfcraft/src/styledxmlparser/css/common_css_constants.dart';
import 'package:pdfcraft/src/styledxmlparser/css/util/css_types_validation_utils.dart';
import 'package:pdfcraft/src/styledxmlparser/exceptions/styled_xml_parser_exception.dart';

/// Utilities class for CSS dimension parsing operations.
class CraftCssDimensionParsingUtils {
  CraftCssDimensionParsingUtils._();

  /// Attempts floating-point parsing without propagating conversion errors.
  static double? parseFloat(String? str) {
    if (str == null) return null;
    return double.tryParse(str);
  }

  /// Parses a length with an allowed metric unit (px, pt, in, cm, mm, pc, q) or numeric value (e.g. 123, 1.23, .123) to pt.
  static double parseAbsoluteLength(String length,
      [String defaultMetric = CraftCommonCssConstants.PX]) {
    int pos = determinePositionBetweenValueAndUnit(length);
    if (pos == 0) {
      throw CraftStyledXMLParserException(
          CraftStyledXMLParserException.NAN.replaceFirst("{0}", length));
    }
    double f = double.parse(length.substring(0, pos));
    String unit = length.substring(pos);

    if (unit.startsWith(CraftCommonCssConstants.PT) ||
        (unit == "" && defaultMetric == CraftCommonCssConstants.PT)) {
      return f;
    }
    if (unit.startsWith(CraftCommonCssConstants.IN) ||
        (unit == "" && defaultMetric == CraftCommonCssConstants.IN)) {
      return f * 72;
    }
    if (unit.startsWith(CraftCommonCssConstants.CM) ||
        (unit == "" && defaultMetric == CraftCommonCssConstants.CM)) {
      return (f / 2.54) * 72;
    }
    if (unit.startsWith(CraftCommonCssConstants.Q) ||
        (unit == "" && defaultMetric == CraftCommonCssConstants.Q)) {
      return (f / 2.54) * 72 / 40;
    }
    if (unit.startsWith(CraftCommonCssConstants.MM) ||
        (unit == "" && defaultMetric == CraftCommonCssConstants.MM)) {
      return (f / 25.4) * 72;
    }
    if (unit.startsWith(CraftCommonCssConstants.PC) ||
        (unit == "" && defaultMetric == CraftCommonCssConstants.PC)) {
      return f * 12;
    }
    if (unit.startsWith(CraftCommonCssConstants.PX) ||
        (unit == "" && defaultMetric == CraftCommonCssConstants.PX)) {
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

    if (unit.startsWith(CraftCommonCssConstants.PERCENTAGE)) {
      return baseValue * f / 100;
    } else if (unit.startsWith(CraftCommonCssConstants.EM) ||
        unit.startsWith(CraftCommonCssConstants.REM)) {
      return baseValue * f;
    } else if (unit.startsWith(CraftCommonCssConstants.EX)) {
      return baseValue * f / 2;
    }
    return f;
  }

  /// Convenience method for parsing a value to pt.
  static CraftUnitValue? parseLengthValueToPt(
      String? value, double emValue, double remValue) {
    if (value == null) return null;
    if (CraftCssTypesValidationUtils.isMetricValue(value) ||
        CraftCssTypesValidationUtils.isNumber(value)) {
      return CraftUnitValue(CraftUnitValue.POINT, parseAbsoluteLength(value));
    } else if (value.endsWith(CraftCommonCssConstants.PERCENTAGE)) {
      return CraftUnitValue(CraftUnitValue.PERCENT,
          double.parse(value.substring(0, value.length - 1)));
    } else if (CraftCssTypesValidationUtils.isRemValue(value)) {
      return CraftUnitValue(
          CraftUnitValue.POINT, parseRelativeValue(value, remValue));
    } else if (CraftCssTypesValidationUtils.isRelativeValue(value)) {
      return CraftUnitValue(
          CraftUnitValue.POINT, parseRelativeValue(value, emValue));
    }
    return null;
  }

  /// Parse length attributes.
  static double parseLength(String length, double percentBaseValue,
      double defaultValue, double fontSize, double rootFontSize) {
    if (CraftCssTypesValidationUtils.isPercentageValue(length)) {
      return parseRelativeValue(length, percentBaseValue);
    } else {
      CraftUnitValue? unitValue =
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
    if (CraftCommonCssConstants.FONT_ABSOLUTE_SIZE_KEYWORDS_VALUES
        .containsKey(fontSizeAttribute)) {
      return parseAbsoluteLength(CraftCommonCssConstants
          .FONT_ABSOLUTE_SIZE_KEYWORDS_VALUES[fontSizeAttribute]!);
    }
    return parseAbsoluteLength(fontSizeAttribute);
  }

  static double parseRelativeFontSize(
      String elementFontSize, double baseFontSize) {
    if (elementFontSize == CraftCommonCssConstants.LARGER) {
      return baseFontSize * 1.2;
    } else if (elementFontSize == CraftCommonCssConstants.SMALLER) {
      return baseFontSize / 1.2;
    }
    return parseRelativeValue(elementFontSize, baseFontSize);
  }
}
