import 'package:collection/collection.dart';
import 'package:dpdf/src/io/util/text_util.dart';

class Glyph {
  static const int REPLACEMENT_CHARACTER = 0xFFFD;
  static final List<int> REPLACEMENT_CHARACTERS = [REPLACEMENT_CHARACTER];
  static final String REPLACEMENT_CHARACTER_STRING =
      String.fromCharCode(REPLACEMENT_CHARACTER);

  final int _code;
  final int _width;
  List<int>? _bbox;
  int _unicode;
  List<int>? _chars;
  final bool _isMark;

  int xPlacement = 0;
  int yPlacement = 0;
  int xAdvance = 0;
  int yAdvance = 0;
  int anchorDelta = 0;

  Glyph(this._code, this._width, this._unicode, [this._bbox])
      : _chars = _unicode > -1 ? TextUtil.convertFromUtf32(_unicode) : null,
        _isMark = false;

  Glyph.withChars(this._code, this._width, List<int>? chars,
      {bool isMark = false})
      : _chars = chars ??
            (chars == null ? null : getCharsFromCodePoint(codePoint(chars))),
        _unicode = codePoint(chars),
        _bbox = null,
        _isMark = isMark;

  Glyph.full(this._code, this._width, this._unicode, this._chars, this._isMark,
      [this._bbox]);

  Glyph.copy(Glyph other)
      : _code = other._code,
        _width = other._width,
        _unicode = other._unicode,
        _chars = other._chars != null ? List.from(other._chars!) : null,
        _isMark = other._isMark,
        _bbox = other._bbox != null ? List.from(other._bbox!) : null,
        xPlacement = other.xPlacement,
        yPlacement = other.yPlacement,
        xAdvance = other.xAdvance,
        yAdvance = other.yAdvance,
        anchorDelta = other.anchorDelta;

  int getCode() => _code;
  int getWidth() => _width;
  List<int>? getBbox() => _bbox;
  bool hasValidUnicode() => _unicode > -1;
  int getUnicode() => _unicode;

  void setUnicode(int unicode) {
    _unicode = unicode;
    _chars = getCharsFromCodePoint(unicode);
  }

  List<int>? getChars() => _chars;
  void setChars(List<int> chars) {
    _chars = chars;
  }

  bool isMark() => _isMark;

  String getUnicodeString() {
    if (_chars != null) {
      return String.fromCharCodes(_chars!);
    } else {
      return REPLACEMENT_CHARACTER_STRING;
    }
  }

  @override
  int get hashCode =>
      Object.hash(_code, _width, const ListEquality().hash(_chars));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Glyph) return false;
    return _code == other._code &&
        _width == other._width &&
        const ListEquality().equals(_chars, other._chars);
  }

  static int codePoint(List<int>? a) {
    if (a != null) {
      if (a.length == 1) {
        return a[0];
      } else if (a.length == 2 &&
          TextUtil.isSurrogateHigh(a[0]) &&
          TextUtil.isSurrogateLow(a[1])) {
        return TextUtil.convertToUtf32(String.fromCharCodes(a), 0);
      }
    }
    return -1;
  }

  static List<int>? getCharsFromCodePoint(int unicode) {
    return unicode > -1 ? TextUtil.convertFromUtf32(unicode) : null;
  }

  @override
  String toString() {
    return "[id=$_code, chars=${_chars}, uni=$_unicode, width=$_width]";
  }
}
