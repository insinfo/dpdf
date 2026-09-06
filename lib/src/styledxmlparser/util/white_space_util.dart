import 'package:dpdf/src/io/util/text_util.dart';

class WhiteSpaceUtil {
  static const Set<int> EM_SPACES = {
    0x2002,
    0x2003,
    0x2009,
  };

  static String collapseConsecutiveSpaces(String s) {
    StringBuffer sb = StringBuffer();
    String? lastChar;
    for (int i = 0; i < s.length; i++) {
      String ch = s[i];
      if (isNonEmSpace(ch)) {
        if (lastChar == null || !isNonEmSpace(lastChar)) {
          sb.write(" ");
          lastChar = " ";
        }
      } else {
        sb.write(ch);
        lastChar = ch;
      }
    }
    return sb.toString();
  }

  static bool isNonEmSpace(String ch) {
    int codeUnit = ch.codeUnitAt(0);
    return TextUtil.isWhiteSpace(codeUnit) && !EM_SPACES.contains(codeUnit);
  }

  static bool isNonLineBreakSpace(String ch) {
    return isNonEmSpace(ch) && ch != '\n';
  }

  static String processWhitespaces(
      String text, bool keepLineBreaks, bool collapseSpaces) {
    if (!keepLineBreaks && collapseSpaces) {
      return collapseConsecutiveSpaces(text);
    } else if (keepLineBreaks && collapseSpaces) {
      StringBuffer sb = StringBuffer();
      String? lastChar;
      for (int i = 0; i < text.length; i++) {
        String ch = text[i];
        if (isNonLineBreakSpace(ch)) {
          if (lastChar == null || lastChar != ' ') {
            sb.write(" ");
            lastChar = ' ';
          }
        } else {
          sb.write(ch);
          lastChar = ch;
        }
      }
      return sb.toString();
    } else {
      return keepLineBreaksAndSpaces(text);
    }
  }

  static String keepLineBreaksAndSpaces(String text) {
    StringBuffer sb = StringBuffer();
    // Prohibit trimming first and last spaces.
    sb.write('\u200d');
    for (int i = 0; i < text.length; i++) {
      sb.write(text[i]);
      if ('\n' == text[i] ||
          ('\r' == text[i] && i + 1 < text.length && '\n' != text[i + 1])) {
        sb.write('\u200d');
      }
    }
    String result = sb.toString();
    if (result.endsWith('\u200d')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
