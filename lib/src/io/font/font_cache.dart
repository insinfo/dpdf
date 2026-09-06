import 'package:dpdf/src/io/font/font_program.dart';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class FontCacheKey {
  final String? name;
  final Uint8List? bytes;

  FontCacheKey(this.name, [this.bytes]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FontCacheKey) return false;
    if (name != null && other.name != null) return name == other.name;
    if (bytes != null && other.bytes != null) {
      // Hash comparison of bytes for performance
      return _hashBytes(bytes!) == _hashBytes(other.bytes!);
    }
    return false;
  }

  @override
  int get hashCode {
    if (name != null) return name.hashCode;
    if (bytes != null) return _hashBytes(bytes!).hashCode;
    return 0;
  }

  static String _hashBytes(Uint8List bytes) {
    return sha1.convert(bytes).toString();
  }
}

class FontCache {
  static final Map<FontCacheKey, FontProgram> _cache = {};

  static FontProgram? getFont(FontCacheKey key) {
    return _cache[key];
  }

  static FontProgram saveFont(FontProgram font, FontCacheKey key) {
    _cache[key] = font;
    return font;
  }

  static void clear() {
    _cache.clear();
  }
}
