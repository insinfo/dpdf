import 'dart:convert';
import '../resources/embedded_font_resources.dart';

class AdobeGlyphList {
  static final Map<int, String> _unicode2names = {};
  static final Map<String, int> _names2unicode = {};
  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    for (final line
        in const LineSplitter().convert(EmbeddedFontResources.glyphList)) {
      if (line.startsWith('#') || line.trim().isEmpty) continue;
      final parts = line.split(';');
      if (parts.length != 2) {
        throw FormatException('Invalid embedded glyph record', line);
      }
      final scalar = parts[1].trim();
      // The scalar API intentionally excludes multi-scalar glyph sequences.
      if (scalar.contains(' ')) continue;
      final value = int.parse(scalar, radix: 16);
      // Process records in source order, retaining historical reverse aliases.
      _unicode2names[value] = parts[0];
      _names2unicode[parts[0]] = value;
    }
    _initialized = true;
  }

  static int nameToUnicode(String name) {
    _ensureInitialized();
    int? v = _names2unicode[name];
    if (v == null && name.length == 7 && name.toLowerCase().startsWith('uni')) {
      try {
        return int.parse(name.substring(3), radix: 16);
      } catch (_) {}
    }
    return v ?? -1;
  }

  static String? unicodeToName(int num) {
    _ensureInitialized();
    return _unicode2names[num];
  }
}
