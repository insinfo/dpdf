import 'dart:typed_data';
import 'abstract_cmap.dart';
import 'cmap_object.dart';
import '../pdf_encodings.dart';
import '../../util/int_hashtable.dart';

/// Stores unsigned, big-endian character codes and their Unicode text.
/// Integer APIs intentionally identify codes by value, not encoded width.
class CMapToUnicode extends AbstractCMap {
  final Map<int, String> _text = {};
  final List<Uint8List> _bounds = [];

  CMapToUnicode();

  static CMapToUnicode getIdentity() {
    final result = CMapToUnicode();
    // Identity covers UTF-16 code units, including surrogate code units.
    for (var unit = 0; unit < 0x10000; unit++) {
      result._text[unit] = String.fromCharCode(unit);
    }
    result.registerCodeInterval(Uint8List(2), Uint8List.fromList([255, 255]));
    return result;
  }

  bool hasByteMappings() => _text.isNotEmpty;

  String? lookup(Uint8List code, [int offset = 0, int? length]) {
    RangeError.checkValueInInterval(offset, 0, code.length, 'offset');
    final count = length ?? code.length - offset;
    RangeError.checkValueInInterval(count, 1, 4, 'length');
    RangeError.checkValidRange(offset, offset + count, code.length);
    return _text[_unsigned(code.getRange(offset, offset + count))];
  }

  String? lookupInt(int code) => _text[code];
  Iterable<int> getCodes() => _text.keys;

  IntHashtable createDirectMapping() {
    final result = IntHashtable();
    for (final pair in _text.entries) {
      final scalar = _singleScalar(pair.value);
      if (scalar != null) result.put(pair.key, scalar);
    }
    return result;
  }

  Map<int, int> createReverseMapping() {
    final result = <int, int>{};
    for (final pair in _text.entries) {
      final scalar = _singleScalar(pair.value);
      if (scalar != null) result[scalar] = pair.key;
    }
    return result;
  }

  List<Uint8List> getCodeSpaceRanges() =>
      _bounds.map(Uint8List.fromList).toList();

  @override
  void registerCodeInterval(Uint8List low, Uint8List high) {
    if (low.isEmpty ||
        low.length > 4 ||
        low.length != high.length ||
        Iterable<int>.generate(low.length).any((i) => low[i] > high[i])) {
      throw ArgumentError(
          'Code space endpoints must have equal widths of 1 to 4 bytes and ascending values.');
    }
    _bounds.addAll([Uint8List.fromList(low), Uint8List.fromList(high)]);
  }

  void addCharInt(int cid, String uni) {
    RangeError.checkValueInInterval(cid, 0, 0xffffffff, 'cid');
    _validateText(uni);
    _text[cid] = uni;
  }

  @override
  void registerMappedCode(String mark, CMapObject code) {
    if (mark.isEmpty || mark.length > 4 || mark.codeUnits.any((n) => n > 255)) {
      throw ArgumentError(
          'A character code must contain 1 to 4 byte-valued characters.');
    }
    final key = _unsigned(mark.codeUnits);
    if (code.isNumber()) {
      final value = code.getValue();
      if (value is! int ||
          value < 0 ||
          value > 0x10ffff ||
          (value >= 0xd800 && value <= 0xdfff)) {
        throw ArgumentError(
            'Numeric Unicode destinations must be scalar values.');
      }
      addCharInt(key, String.fromCharCode(value));
    } else if (code.isString()) {
      final raw = code.getValue();
      final List<int> bytes =
          raw is List<int> ? raw : code.toString().codeUnits;
      if (bytes.any((n) => n < 0 || n > 255)) {
        throw FormatException('A CMap string contains a non-byte value.');
      }
      final bom = bytes.length >= 2 && bytes[0] == 254 && bytes[1] == 255;
      String decoded;
      if (code.isHexString() || bom || bytes.length.isEven) {
        final start = !code.isHexString() && bom ? 2 : 0;
        if ((bytes.length - start).isOdd) {
          throw FormatException(
              'A UTF-16BE destination has an incomplete code unit.');
        }
        decoded = String.fromCharCodes([
          for (var i = start; i < bytes.length; i += 2)
            bytes[i] * 256 + bytes[i + 1]
        ]);
      } else {
        decoded = PdfEncodings.convertToString(
            Uint8List.fromList(bytes), PdfEncodings.PDF_DOC_ENCODING);
      }
      addCharInt(key, decoded);
    } else {
      throw ArgumentError(
          'A Unicode destination must be a string or scalar number.');
    }
  }

  static int _unsigned(Iterable<int> bytes) {
    var value = 0;
    for (final byte in bytes) {
      value = value * 256 + byte;
    }
    return value;
  }

  static void _validateText(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i == text.length ||
            text.codeUnitAt(i) < 0xdc00 ||
            text.codeUnitAt(i) > 0xdfff) {
          throw FormatException(
              'Unicode text contains an unmatched high surrogate.');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw FormatException(
            'Unicode text contains an unmatched low surrogate.');
      }
    }
  }

  static int? _singleScalar(String text) {
    if (text.length == 1) {
      final unit = text.codeUnitAt(0);
      return unit >= 0xd800 && unit <= 0xdfff ? null : unit;
    }
    if (text.length == 2) {
      final high = text.codeUnitAt(0), low = text.codeUnitAt(1);
      if (high >= 0xd800 && high <= 0xdbff && low >= 0xdc00 && low <= 0xdfff) {
        return 0x10000 + (high - 0xd800) * 1024 + low - 0xdc00;
      }
    }
    return null;
  }
}
