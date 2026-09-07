import 'cjk_resource_loader.dart';
import 'pdf_encodings.dart';

class CidFontProperties {
  static Map<String, Map<String, dynamic>> getAllFonts() {
    CjkResourceLoader.initSync();
    return CjkResourceLoader.allCidFonts;
  }

  static Map<String, Set<String>> getRegistryNames() {
    CjkResourceLoader.initSync();
    return CjkResourceLoader.registryNames;
  }

  static bool isCjkFont(String fontName) {
    CjkResourceLoader.initSync();
    final fonts = CjkResourceLoader.registryNames[CjkResourceLoader.FONTS_PROP];
    return fonts != null && fonts.contains(fontName);
  }

  /// Checks if its a valid CJKFont font.
  static bool isCidFont(String fontName, String enc) {
    CjkResourceLoader.initSync();
    final fonts = CjkResourceLoader.registryNames[CjkResourceLoader.FONTS_PROP];
    if (fonts == null || !fonts.contains(fontName)) {
      return false;
    }
    if (enc == PdfEncodings.IDENTITY_H || enc == PdfEncodings.IDENTITY_V) {
      return true;
    }
    final fontProps = CjkResourceLoader.allCidFonts[fontName];
    if (fontProps == null) return false;
    final registry = fontProps[CjkResourceLoader.REGISTRY_PROP] as String?;
    if (registry == null) return false;
    final encodings = CjkResourceLoader.registryNames[registry];
    return encodings != null && encodings.contains(enc);
  }

  static String? getCompatibleFont(String enc) {
    CjkResourceLoader.initSync();
    for (final entry in CjkResourceLoader.registryNames.entries) {
      if (entry.value.contains(enc)) {
        final registry = entry.key;
        for (final fontEntry in CjkResourceLoader.allCidFonts.entries) {
          if (registry == fontEntry.value[CjkResourceLoader.REGISTRY_PROP]) {
            return fontEntry.key;
          }
        }
      }
    }
    return null;
  }
}
