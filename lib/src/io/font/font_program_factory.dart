import 'dart:typed_data';
import 'package:pdfcraft/src/io/font/font_program.dart';
import 'package:pdfcraft/src/io/font/true_type_font.dart';
import 'package:pdfcraft/src/io/font/type1_font.dart';
import 'package:pdfcraft/src/io/font/constants/standard_fonts.dart';
import 'package:pdfcraft/src/io/font/font_cache.dart';

class CraftFontProgramFactory {
  static const bool DEFAULT_CACHED = true;

  static CraftFontProgram createFont(String fontName,
      [bool cached = DEFAULT_CACHED]) {
    if (cached) {
      final key = CraftFontCacheKey(fontName);
      final cachedFont = CraftFontCache.resolveTypeface(key);
      if (cachedFont != null) return cachedFont;
    }

    CraftFontProgram font;
    if (CraftStandardFonts.isStandardFont(fontName)) {
      font = CraftType1Font.createBuiltInFont(fontName);
    } else {
      if (fontName.toLowerCase().endsWith(".ttf") ||
          fontName.toLowerCase().endsWith(".otf")) {
        font = CraftTrueTypeFont.fromFile(fontName);
      } else {
        // Default to Type1 or throw
        throw Exception("Font type not recognized for: $fontName");
      }
    }

    if (cached) {
      CraftFontCache.saveFont(font, CraftFontCacheKey(fontName));
    }
    return font;
  }

  static CraftFontProgram createFontFromBytes(Uint8List bytes,
      [bool cached = DEFAULT_CACHED]) {
    if (cached) {
      final key = CraftFontCacheKey(null, bytes);
      final cachedFont = CraftFontCache.resolveTypeface(key);
      if (cachedFont != null) return cachedFont;
    }

    // Try TrueType first
    CraftFontProgram font;
    try {
      font = CraftTrueTypeFont.fromBytes(bytes);
    } catch (e) {
      // Try Type1?
      // For now just rethrow or try Type1 if we have a parser that works with bytes.
      rethrow;
    }

    if (cached) {
      CraftFontCache.saveFont(font, CraftFontCacheKey(null, bytes));
    }
    return font;
  }
}
