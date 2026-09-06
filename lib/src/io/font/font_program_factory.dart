import 'dart:typed_data';
import 'package:dpdf/src/io/font/font_program.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/io/font/type1_font.dart';
import 'package:dpdf/src/io/font/constants/standard_fonts.dart';
import 'package:dpdf/src/io/font/font_cache.dart';

class FontProgramFactory {
  static const bool DEFAULT_CACHED = true;

  static FontProgram createFont(String fontName,
      [bool cached = DEFAULT_CACHED]) {
    if (cached) {
      final key = FontCacheKey(fontName);
      final cachedFont = FontCache.getFont(key);
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
      final cachedFont = FontCache.getFont(key);
      if (cachedFont != null) return cachedFont;
    }

    // Try TrueType first
    FontProgram font;
    try {
      font = TrueTypeFont.fromBytes(bytes);
    } catch (e) {
      // Try Type1?
      // For now just rethrow or try Type1 if we have a parser that works with bytes.
      rethrow;
    }

    if (cached) {
      FontCache.saveFont(font, FontCacheKey(null, bytes));
    }
    return font;
  }
}
