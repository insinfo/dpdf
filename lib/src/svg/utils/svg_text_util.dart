import 'package:dpdf/src/io/util/text_util.dart';

class SvgTextUtil {
  SvgTextUtil._();

  /// Trim all the leading whitespace characters from the passed string
  static String trimLeadingWhitespace(String? toTrim) {
    if (toTrim == null) {
      return "";
    }
    int current = 0;
    int end = toTrim.length;
    while (current < end) {
      int currentChar = toTrim.codeUnitAt(current);
      if (TextUtil.isWhiteSpace(currentChar) &&
          !(currentChar == 10 || currentChar == 13)) {
        current++;
      } else {
        break;
      }
    }
    return toTrim.substring(current);
  }

  /// Trim all the trailing whitespace characters from the passed string
  static String trimTrailingWhitespace(String? toTrim) {
    if (toTrim == null) {
      return "";
    }
    int end = toTrim.length;
    if (end > 0) {
      int current = end - 1;
      while (current >= 0) {
        int currentChar = toTrim.codeUnitAt(current);
        if (TextUtil.isWhiteSpace(currentChar) &&
            !(currentChar == 10 || currentChar == 13)) {
          current--;
        } else {
          break;
        }
      }
      if (current < 0) {
        return "";
      } else {
        return toTrim.substring(0, current + 1);
      }
    } else {
      return toTrim;
    }
  }

  /// The reference value may contain a hashtag character or 'url' designation and this method will filter them.
  static String filterReferenceValue(String name) {
    return name
        .replaceAll("#", "")
        .replaceAll("url(", "")
        .replaceAll(")", "")
        .trim();
  }
}
