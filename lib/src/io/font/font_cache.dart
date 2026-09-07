import 'package:dpdf/src/io/font/font_program.dart';
import 'dart:typed_data';
import '../../commons/digest/digest_bytes.dart';

class CraftFontCacheKey {
  final String? name;
  final Uint8List? bytes;

  CraftFontCacheKey(this.name, [this.bytes]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CraftFontCacheKey) return false;
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
    return DigestBytes.compute('SHA-1', bytes)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

class CraftFontCache {
  static final Map<CraftFontCacheKey, CraftFontProgram> _cache = {};

  static CraftFontProgram? resolveTypeface(CraftFontCacheKey key) {
    return _cache[key];
  }

  static CraftFontProgram saveFont(
      CraftFontProgram font, CraftFontCacheKey key) {
    _cache[key] = font;
    return font;
  }

  static void clear() {
    _cache.clear();
  }
}
