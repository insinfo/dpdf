import 'cjk_resource_loader.dart';
import 'pdf_encodings.dart';

class CraftCidFontProperties {
  static Map<String, Map<String, dynamic>> getAllFonts() {
    CraftCjkResourceLoader.initSync();
    return CraftCjkResourceLoader.allCidFonts;
  }

  static Map<String, Set<String>> getRegistryNames() {
    CraftCjkResourceLoader.initSync();
    return CraftCjkResourceLoader.registryNames;
  }

  static bool isCjkFont(String fontName) {
    CraftCjkResourceLoader.initSync();
    final fonts =
        CraftCjkResourceLoader.registryNames[CraftCjkResourceLoader.FONTS_PROP];
    return fonts != null && fonts.contains(fontName);
  }

  /// Checks if its a valid CJKFont font.
  static bool isCidFont(String fontName, String enc) {
    CraftCjkResourceLoader.initSync();
    final fonts =
        CraftCjkResourceLoader.registryNames[CraftCjkResourceLoader.FONTS_PROP];
    if (fonts == null || !fonts.contains(fontName)) {
      return false;
    }
    if (enc == CraftPdfEncodings.IDENTITY_H ||
        enc == CraftPdfEncodings.IDENTITY_V) {
      return true;
    }
    final fontProps = CraftCjkResourceLoader.allCidFonts[fontName];
    if (fontProps == null) return false;
    final registry = fontProps[CraftCjkResourceLoader.REGISTRY_PROP] as String?;
    if (registry == null) return false;
    final encodings = CraftCjkResourceLoader.registryNames[registry];
    return encodings != null && encodings.contains(enc);
  }

  static String? getCompatibleFont(String enc) {
    CraftCjkResourceLoader.initSync();
    for (final entry in CraftCjkResourceLoader.registryNames.entries) {
      if (entry.value.contains(enc)) {
        final registry = entry.key;
        for (final fontEntry in CraftCjkResourceLoader.allCidFonts.entries) {
          if (registry ==
              fontEntry.value[CraftCjkResourceLoader.REGISTRY_PROP]) {
            return fontEntry.key;
          }
        }
      }
    }
    return null;
  }
}
