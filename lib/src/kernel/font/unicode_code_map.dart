import 'dart:typed_data';
import '../../io/font/cmap/abstract_cmap.dart';
import '../../io/font/cmap/cmap_object.dart';
import '../../io/font/cmap/cmap_parser.dart';
import '../../io/font/cmap/cmap_location_from_bytes.dart';
import '../pdf/pdf_stream.dart';

/// Character-code mappings with validated Unicode values and exact replacement.
/// A source code is unsigned and contains at most four bytes.
class UnicodeCodeMap extends CraftAbstractCMap {
  final Map<int, String> _text = {};

  Map<int, String> get mappings => Map.unmodifiable(_text);

  String textForCode(int code) => _text[code] ?? '';

  /// Null denotes absence, allowing source code zero to remain distinguishable.
  int? codeForText(String text) {
    for (final entry in _text.entries) {
      if (entry.value == text) return entry.key;
    }
    return null;
  }

  int? codeForScalar(int scalar) =>
      _validScalar(scalar) ? codeForText(String.fromCharCode(scalar)) : null;

  bool hasSequence(int code) => (_text[code]?.runes.length ?? 0) > 1;

  String decodeCodes(Iterable<int> codes) => codes.map(textForCode).join();

  void setScalar(int code, int scalar) {
    if (!_validScalar(scalar)) {
      throw RangeError.value(scalar, 'scalar', 'Expected a Unicode scalar');
    }
    setMapping(code, String.fromCharCode(scalar));
  }

  /// Validates before replacing; an empty value removes an existing entry.
  void setMapping(int code, String text) {
    if (code < 0 || code > 0xffffffff) {
      throw RangeError.range(code, 0, 0xffffffff, 'code');
    }
    _validateUnits(text.codeUnits);
    if (text.isEmpty) {
      _text.remove(code);
    } else {
      _text[code] = text;
    }
  }

  @override
  void registerMappedCode(String mark, CraftCMapObject destination) {
    final source = mark.codeUnits;
    if (source.isEmpty || source.length > 4 || source.any((v) => v > 255)) {
      throw FormatException('Mapping source must contain one to four bytes.');
    }
    final code = source.fold<int>(0, (value, byte) => value * 256 + byte);
    final payload = destination.getValue();
    if (destination.isNumber() && payload is int) {
      setScalar(code, payload);
      return;
    }
    if (!destination.isString()) {
      throw FormatException(
          'Unicode mapping destination must be text or a scalar.');
    }
    final List<int> bytes;
    if (payload is String) {
      bytes = payload.codeUnits;
    } else if (payload is List<int>) {
      bytes = payload;
    } else {
      throw FormatException(
          'Unicode mapping destination has no byte representation.');
    }
    if (bytes.length.isOdd || bytes.any((v) => v < 0 || v > 255)) {
      throw FormatException(
          'Unicode mapping must contain complete UTF-16BE byte pairs.');
    }
    final start =
        bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff ? 2 : 0;
    final units = <int>[
      for (var offset = start; offset < bytes.length; offset += 2)
        bytes[offset] * 256 + bytes[offset + 1],
    ];
    _validateUnits(units);
    setMapping(code, String.fromCharCodes(units));
  }

  static Future<UnicodeCodeMap> fromStream(CraftPdfStream stream) async {
    final bytes = await stream.getBytes();
    if (bytes == null)
      throw FormatException('Unicode mapping stream has no data.');
    final map = UnicodeCodeMap();
    await CraftCMapParser.loadCidMappings(
        '', map, CraftCMapLocationFromBytes(bytes));
    return map;
  }

  static UnicodeCodeMap fromBytes(Uint8List bytes) {
    final map = UnicodeCodeMap();
    CraftCMapParser.loadCidMappingsSync(
        '', map, CraftCMapLocationFromBytes(bytes));
    return map;
  }

  static bool _validScalar(int value) =>
      value >= 0 && value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff);

  static void _validateUnits(List<int> units) {
    var expectsLow = false;
    for (final unit in units) {
      if (expectsLow) {
        if (unit < 0xdc00 || unit > 0xdfff) {
          throw FormatException(
              'Unicode text contains an incomplete surrogate pair.');
        }
        expectsLow = false;
      } else if (unit >= 0xd800 && unit <= 0xdbff) {
        expectsLow = true;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw FormatException(
            'Unicode text starts a pair with a low surrogate.');
      }
    }
    if (expectsLow)
      throw FormatException('Unicode text ends with a high surrogate.');
  }
}
