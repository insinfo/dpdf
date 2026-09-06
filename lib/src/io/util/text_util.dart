import 'dart:typed_data';

class TextUtil {
  static const int CHARACTER_MIN_SUPPLEMENTARY_CODE_POINT = 0x010000;

  static const Set<int> _javaNonUnicodeCategoryWhiteSpaceChars = {
    0x0009, // HORIZONTAL TABULATION
    0x000A, // LINE FEED
    0x000B, // VERTICAL TABULATION
    0x000C, // FORM FEED
    0x000D, // CARRIAGE RETURN
    0x001C, // FILE SEPARATOR
    0x001D, // GROUP SEPARATOR
    0x001E, // RECORD SEPARATOR
    0x001F, // UNIT SEPARATOR
  };

  static final Set<int> _ignorableCodePoints = {
    0x0000,
    0x0001,
    0x0002,
    0x0003,
    0x0004,
    0x0005,
    0x0006,
    0x0007,
    0x0008,
    0x000E,
    0x000F,
    0x0010,
    0x0011,
    0x0012,
    0x0013,
    0x0014,
    0x0015,
    0x0016,
    0x0017,
    0x0018,
    0x0019,
    0x001A,
    0x001B,
    0x007F,
    0x0080,
    0x0081,
    0x0082,
    0x0083,
    0x0084,
    0x0085,
    0x0086,
    0x0087,
    0x0088,
    0x0089,
    0x008A,
    0x008B,
    0x008C,
    0x008D,
    0x008E,
    0x008F,
    0x0090,
    0x0091,
    0x0092,
    0x0093,
    0x0094,
    0x0095,
    0x0096,
    0x0097,
    0x0098,
    0x0099,
    0x009A,
    0x009B,
    0x009C,
    0x009D,
    0x009E,
    0x009F,
    0x00AD,
    0x0600,
    0x0601,
    0x0602,
    0x0603,
    0x06DD,
    0x070F,
    0x17B4,
    0x17B5,
    0x200B,
    0x200C,
    0x200D,
    0x200E,
    0x200F,
    0x202A,
    0x202B,
    0x202C,
    0x202D,
    0x202E,
    0x2060,
    0x2061,
    0x2062,
    0x2063,
    0x2064,
    0x206A,
    0x206B,
    0x206C,
    0x206D,
    0x206E,
    0x206F,
    0xFEFF,
    0xFFF9,
    0xFFFa,
    0xFFFb,
    0x110BD,
    0x1D173,
    0x1D174,
    0x1D175,
    0x1D176,
    0x1D177,
    0x1D178,
    0x1D179,
    0x1D17A,
    0xE0001
  };

  static bool isSurrogateHigh(int c) {
    return c >= 0xD800 && c <= 0xDBFF;
  }

  static bool isSurrogateLow(int c) {
    return c >= 0xDC00 && c <= 0xDFFF;
  }

  static bool isSurrogatePair(String text, int idx) {
    if (idx < 0 || idx > text.length - 2) {
      return false;
    }
    return isSurrogateHigh(text.codeUnitAt(idx)) &&
        isSurrogateLow(text.codeUnitAt(idx + 1));
  }

  static int convertToUtf32(String text, int idx) {
    int high = text.codeUnitAt(idx);
    int low = text.codeUnitAt(idx + 1);
    return (high - 0xD800) * 0x400 + low - 0xDC00 + 0x10000;
  }

  static Uint16List convertFromUtf32(int codePoint) {
    if (codePoint < 0x10000) {
      return Uint16List.fromList([codePoint]);
    }
    codePoint -= 0x10000;
    return Uint16List.fromList(
        [(codePoint ~/ 0x400) + 0xD800, (codePoint % 0x400) + 0xDC00]);
  }

  static bool isWhiteSpace(int unicode) {
    if (unicode == 0x00A0 || unicode == 0x2007 || unicode == 0x202F) {
      return false;
    }
    // Simple check for now, can expand with regex or strict category check if needed
    // Dart's regex \s matches whitespaces
    // return RegExp(r'\s').hasMatch(String.fromCharCode(unicode));

    // Explicit check for common ones + java set
    if (unicode <= 0xFFFF &&
        _javaNonUnicodeCategoryWhiteSpaceChars.contains(unicode)) {
      return true;
    }

    // Fallback to basic space
    return unicode == 32;
  }

  static bool isIdentifierIgnorable(int codePoint) {
    if (codePoint >= 0xE0020 && codePoint <= 0xE007F) return true;
    return _ignorableCodePoints.contains(codePoint);
  }

  static bool isWhitespaceOrNonPrintable(int code) {
    return isWhiteSpace(code) || isNonPrintable(code);
  }

  static bool isNonPrintable(int c) {
    return isIdentifierIgnorable(c) || c == 0x00AD;
  }
}
