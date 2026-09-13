import 'dart:typed_data';
import 'package:dpdf/src/io/font/font_program.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/io/font/type1_font.dart';
import 'package:dpdf/src/io/font/constants/standard_fonts.dart';
import 'package:dpdf/src/io/font/font_cache.dart';
import 'package:dpdf/src/io/font/true_type_collection.dart';
import 'package:dpdf/src/io/font/woff_converter.dart';
import 'package:dpdf/src/platform/io.dart';

class FontProgramFactory {
  static const bool DEFAULT_CACHED = true;

  /// A path that names one font of a collection, `fonts/NotoSans.ttc,1`.
  ///
  /// A collection file holds several fonts, so a path alone does not identify
  /// one; the trailing index is the convention this package follows, and the
  /// part before the comma is the file.
  static final RegExp _collectionPath =
      RegExp(r'^(.*\.(?:ttc|otc)),(\d+)$', caseSensitive: false);

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
      final selection = _collectionPath.firstMatch(fontName);
      final lower = fontName.toLowerCase();
      if (selection != null) {
        font = openCollection(_read(selection.group(1)!))
            .getFont(int.parse(selection.group(2)!));
      } else if (lower.endsWith('.ttc') || lower.endsWith('.otc')) {
        // Without a selector a collection still has to open as something,
        // and the first font is the one a collection leads with.
        font = openCollection(_read(fontName)).getFont(0);
      } else if (lower.endsWith(".ttf") || lower.endsWith(".otf")) {
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
    // the sfnt reader ever sees it. What comes out may be a collection, in
    // which case the first font of it is the program this call asked for.
    final sfnt = WoffConverter.toSfnt(bytes);
    FontProgram font = TrueTypeCollection.isCollection(sfnt)
        ? TrueTypeCollection.fromBytes(sfnt).getFont(0)
        : TrueTypeFont.fromBytes(sfnt);

    if (cached) {
      FontCache.saveFont(font, FontCacheKey(null, bytes));
    }
    return font;
  }

  /// The font collection held in [bytes], unwrapping a WOFF 2.0 file first if
  /// that is what [bytes] are.
  ///
  /// WOFF 2.0 can wrap a collection, and [WoffConverter.toSfnt] rebuilds it
  /// as a `ttcf` file, so both forms reach this the same way.
  static TrueTypeCollection openCollection(Uint8List bytes) =>
      TrueTypeCollection.fromBytes(WoffConverter.toSfnt(bytes));

  /// One font of the collection held in [bytes], chosen by [index] or, when
  /// [name] is given, by PostScript name, full name or family name.
  ///
  /// The fonts of a collection share tables, so the collection is read once
  /// and the chosen font reads it in place. Nothing is cached here: two calls
  /// asking for different fonts of the same bytes would otherwise collide on
  /// the one cache key those bytes have.
  static FontProgram createFontFromCollection(Uint8List bytes,
      {int index = 0, String? name}) {
    final collection = openCollection(bytes);
    return name == null
        ? collection.getFont(index)
        : collection.getFontByName(name);
  }

  static Uint8List _read(String path) => File(path).readAsBytesSync();
}
