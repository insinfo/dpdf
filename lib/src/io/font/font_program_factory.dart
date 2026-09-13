import 'dart:typed_data';
import 'package:dpdf/src/io/font/font_program.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/io/font/type1_font.dart';
import 'package:dpdf/src/io/font/constants/standard_fonts.dart';
import 'package:dpdf/src/io/font/font_cache.dart';
import 'package:dpdf/src/io/font/woff_converter.dart';

class FontProgramFactory {
  static const bool DEFAULT_CACHED = true;

  static FontProgram createFont(String fontName,
      [bool cached = DEFAULT_CACHED]) {
    if (cached) {
      final key = FontCacheKey(fontName);
      final cachedFont = FontCache.resolveTypeface(key);
      if (cachedFont != null) return cachedFont;
    }

    FontProgram font;
    if (StandardFonts.isStandardFont(fontName)) {
      font = Type1Font.createBuiltInFont(fontName);
    } else {
      if (fontName.toLowerCase().endsWith(".ttf") ||
          fontName.toLowerCase().endsWith(".otf")) {
        font = TrueTypeFont.fromFile(fontName);
      } else {
        // Default to Type1 or throw
        throw Exception("Font type not recognized for: $fontName");
      }
    }

    if (cached) {
      FontCache.saveFont(font, FontCacheKey(fontName));
    }
    return font;
  }

  static FontProgram createFontFromBytes(Uint8List bytes,
      [bool cached = DEFAULT_CACHED]) {
    if (cached) {
      final key = FontCacheKey(null, bytes);
      final cachedFont = FontCache.resolveTypeface(key);
      if (cachedFont != null) return cachedFont;
    }

    // A WOFF wrapper holds an ordinary sfnt font, so it is unwrapped before
    // the sfnt reader ever sees it.
    FontProgram font = TrueTypeFont.fromBytes(WoffConverter.toSfnt(bytes));

    if (cached) {
      FontCache.saveFont(font, FontCacheKey(null, bytes));
    }
    return font;
  }
}
