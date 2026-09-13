import 'dart:convert';
import '../resources/embedded_font_resources.dart';

class AdobeGlyphList {
  static final Map<int, String> _unicode2names = {};
  static final Map<String, int> _names2unicode = {};
  static bool _initialized = false;

  /// Glyph names built from hexadecimal scalars, as used by the algorithm
  /// ISO 32000-1:2008, 9.10.2 relies on when a name is absent from the list.
  static final RegExp _uniformScalars = RegExp(r'^uni([0-9A-Fa-f]{4})+$');
  static final RegExp _singleScalar = RegExp(r'^u([0-9A-Fa-f]{4,6})$');

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

  /// The single scalar [name] stands for, or -1 when it stands for none or
  /// for a sequence of several. Names absent from the list are resolved by
  /// the conventional constructions `uniXXXX` and `uXXXX` to `uXXXXXX`.
  static int nameToUnicode(String name) {
    final text = nameToUnicodeText(name);
    if (text == null) return -1;
    if (text.runes.length != 1) return -1;
    return text.runes.first;
  }

  /// The text [name] stands for, or `null` when the name cannot be resolved.
  ///
  /// Implements the glyph-name conventions a conforming reader applies when
  /// building the reverse mapping of 9.10.2, "Mapping character codes to
  /// Unicode values": a trailing variant suffix is dropped, underscores
  /// separate the components of a ligature name, and the remaining
  /// components are looked up in the Adobe Glyph List or decoded from their
  /// hexadecimal spelling.
  static String? nameToUnicodeText(String name) {
    _ensureInitialized();
    if (name.isEmpty) return null;
    // A period introduces a variant suffix ("a.sc"); it is never part of the
    // base name. A bare ".notdef" has no text of its own.
    final period = name.indexOf('.');
    final base = period < 0 ? name : name.substring(0, period);
    if (base.isEmpty) return null;
    final result = StringBuffer();
    for (final component in base.split('_')) {
      final text = _componentToText(component);
      if (text == null) return null;
      result.write(text);
    }
    return result.toString();
  }

  static String? _componentToText(String component) {
    if (component.isEmpty) return null;
    final listed = _names2unicode[component];
    if (listed != null) return String.fromCharCode(listed);
    if (_uniformScalars.hasMatch(component)) {
      final scalars = <int>[];
      for (var digit = 3; digit < component.length; digit += 4) {
        final value = int.parse(component.substring(digit, digit + 4),
            radix: 16);
        // Surrogate code units are not characters; such a name is unusable.
        if (value >= 0xd800 && value <= 0xdfff) return null;
        scalars.add(value);
      }
      return String.fromCharCodes(scalars);
    }
    final single = _singleScalar.firstMatch(component);
    if (single != null) {
      final value = int.parse(single.group(1)!, radix: 16);
      if (value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) return null;
      return String.fromCharCode(value);
    }
    return null;
  }

  static String? unicodeToName(int num) {
    _ensureInitialized();
    return _unicode2names[num];
  }
}
