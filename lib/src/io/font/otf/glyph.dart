import 'package:dpdf/src/commons/utils/value_collections.dart';
import 'package:dpdf/src/io/util/text_util.dart';

class CraftGlyph {
  static const int REPLACEMENT_CHARACTER = 0xFFFD;
  static final List<int> REPLACEMENT_CHARACTERS = [REPLACEMENT_CHARACTER];
  static final String REPLACEMENT_CHARACTER_STRING =
      String.fromCharCode(REPLACEMENT_CHARACTER);

  final int _code;
  final int _width;
  final List<int>? _bbox;
  int _unicode;
  List<int>? _chars;
  final bool _isMark;

  int xPlacement = 0;
  int yPlacement = 0;
  int xAdvance = 0;
  int yAdvance = 0;
  int anchorDelta = 0;

  CraftGlyph(this._code, this._width, this._unicode, [this._bbox])
      : _chars =
            _unicode > -1 ? CraftTextUtil.convertFromUtf32(_unicode) : null,
        _isMark = false;

  CraftGlyph.withOffsets(
      this._code,
      this._width,
      this._unicode,
      this._bbox,
      this.xPlacement,
      this.yPlacement,
      this.xAdvance,
      this.yAdvance,
      this.anchorDelta)
      : _chars =
            _unicode > -1 ? CraftTextUtil.convertFromUtf32(_unicode) : null,
        _isMark = false;

  CraftGlyph.withChars(this._code, this._width, List<int>? chars,
      {bool isMark = false})
      : _chars = chars ??
            (chars == null ? null : getCharsFromCodePoint(codePoint(chars))),
        _unicode = codePoint(chars),
        _bbox = null,
        _isMark = isMark;

  CraftGlyph.full(
      this._code, this._width, this._unicode, this._chars, this._isMark,
      [this._bbox]);

  CraftGlyph.copy(CraftGlyph other)
      : _code = other._code,
        _width = other._width,
        _unicode = other._unicode,
        _chars = other._chars != null ? List.from(other._chars!) : null,
        _isMark = other._isMark,
        _bbox = other._bbox != null ? List.from(other._bbox) : null,
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

  int getXPlacement() => xPlacement;
  void setXPlacement(int value) => xPlacement = value;

  int getYPlacement() => yPlacement;
  void setYPlacement(int value) => yPlacement = value;

  int getXAdvance() => xAdvance;
  void setXAdvance(int value) => xAdvance = value;

  int getYAdvance() => yAdvance;
  void setYAdvance(int value) => yAdvance = value;

  int getAnchorDelta() => anchorDelta;
  void setAnchorDelta(int value) => anchorDelta = value;

  bool hasOffsets() => hasAdvance() || hasPlacement();

  bool hasPlacement() => xPlacement != 0 || yPlacement != 0 || anchorDelta != 0;

  bool hasAdvance() => xAdvance != 0 || yAdvance != 0;

  String getUnicodeString() {
    if (_chars != null) {
      return String.fromCharCodes(_chars!);
    } else {
      return REPLACEMENT_CHARACTER_STRING;
    }
  }

  @override
  int get hashCode =>
      Object.hash(_code, _width, ValueCollections.listHash(_chars));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CraftGlyph) return false;
    return _code == other._code &&
        _width == other._width &&
        ValueCollections.listsEqual(_chars, other._chars);
  }

  static int codePoint(List<int>? a) {
    if (a != null) {
      if (a.length == 1) {
        return a[0];
      } else if (a.length == 2 &&
          CraftTextUtil.isSurrogateHigh(a[0]) &&
          CraftTextUtil.isSurrogateLow(a[1])) {
        return CraftTextUtil.convertToUtf32(String.fromCharCodes(a), 0);
      }
    }
    return -1;
  }

  static List<int>? getCharsFromCodePoint(int unicode) {
    return unicode > -1 ? CraftTextUtil.convertFromUtf32(unicode) : null;
  }

  @override
  String toString() {
    return "[id=$_code, chars=$_chars, uni=$_unicode, width=$_width]";
  }
}
