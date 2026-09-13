import 'dart:typed_data';
import 'package:dpdf/src/io/font/adobe_glyph_list.dart';
import 'package:dpdf/src/io/font/base_encodings.dart';
import 'package:dpdf/src/io/font/pdf_encodings.dart';
import 'package:dpdf/src/io/font/otf/glyph_line.dart';

import 'package:dpdf/src/io/util/text_util.dart';

/// The association between one-byte character codes and glyph descriptions
/// that ISO 32000-1:2008, 9.6.6, "Character Encoding" defines for simple
/// fonts.
///
/// The table of glyph names in [differences] is the authoritative part: a
/// Type 1 or Type 3 program is keyed by glyph name, and 9.6.6.4 reaches a
/// TrueType glyph through a name as well. [codeToUnicode] and
/// [unicodeToCode] are derived from it through the Adobe Glyph List.
class FontEncoding {
  static const String NOTDEF = ".notdef";
  static const String FONT_SPECIFIC = "FontSpecific";

  String? baseEncoding;
  bool fontSpecific = false;

  Map<int, int> unicodeToCode = {};
  List<int> codeToUnicode = List.filled(256, -1);
  List<String?> differences = List.filled(256, null); // Array of strings
  Map<int, int> unicodeDifferences = {};

  FontEncoding() {
    // Default init
  }

  static FontEncoding createFontEncoding(String baseEncoding) {
    FontEncoding encoding = FontEncoding();
    encoding.baseEncoding = normalizeEncoding(baseEncoding);
    if (encoding.baseEncoding!.startsWith("#")) {
      encoding.fillCustomEncoding();
    } else {
      encoding.fillNamedEncoding();
    }
    return encoding;
  }

  static FontEncoding createEmptyFontEncoding() {
    FontEncoding encoding = FontEncoding();
    encoding.baseEncoding = null;
    encoding.fontSpecific = false;
    for (int ch = 0; ch < 256; ch++) {
      encoding.unicodeDifferences[ch] = ch;
    }
    return encoding;
  }

  static FontEncoding createFontSpecificEncoding() {
    FontEncoding encoding = FontEncoding();
    encoding.fontSpecific = true;
    fillFontEncoding(encoding);
    return encoding;
  }

  /// Resolves the encoding of a simple font as 9.6.6.1 prescribes.
  ///
  /// [baseEncoding] is the `/Encoding` name, or the `/BaseEncoding` entry of
  /// an encoding dictionary (Table 114); [differences] is that dictionary's
  /// `/Differences` array, already flattened by [flattenDifferences].
  /// [builtIn] is the font program's own encoding, which is the implicit
  /// base whenever the program is embedded. When no base encoding is named
  /// and the program supplies none, a nonsymbolic font falls back to
  /// StandardEncoding and a symbolic one stays font-specific.
  ///
  /// [fillUndefinedFromStandard] applies the last step that 9.6.6.4
  /// prescribes for TrueType programs: "any undefined entries in the table
  /// shall be filled using StandardEncoding".
  static FontEncoding createEncoding({
    String? baseEncoding,
    Map<int, String>? differences,
    List<String?>? builtIn,
    bool symbolic = false,
    bool fillUndefinedFromStandard = false,
  }) {
    final encoding = FontEncoding();
    final named = BaseEncodings.canonicalName(normalizeEncoding(baseEncoding));
    List<String?>? table;
    if (named != null && BaseEncodings.predefinedNames.contains(named)) {
      encoding.baseEncoding = normalizeEncoding(baseEncoding);
      table = BaseEncodings.byName(named);
    } else if (builtIn != null) {
      table = builtIn;
      encoding.fontSpecific = symbolic;
    } else if (named != null) {
      // StandardEncoding and the two symbol sets are not permitted /Encoding
      // values, but they do name a table this package can supply.
      encoding.baseEncoding = normalizeEncoding(baseEncoding);
      table = BaseEncodings.byName(named);
      encoding.fontSpecific = named == BaseEncodings.symbolEncoding ||
          named == BaseEncodings.zapfDingbatsEncoding;
    } else if (!symbolic) {
      table = BaseEncodings.standard;
    } else {
      encoding.fontSpecific = true;
    }

    if (table != null) {
      for (var code = 0; code < 256; code++) {
        encoding.differences[code] = table[code];
      }
    }
    if (differences != null) {
      differences.forEach((code, name) {
        if (code >= 0 && code < 256) encoding.differences[code] = name;
      });
    }
    if (fillUndefinedFromStandard) {
      final standard = BaseEncodings.standard;
      for (var code = 0; code < 256; code++) {
        encoding.differences[code] ??= standard[code];
      }
    }
    encoding._rebuildUnicodeMappings(
        canonical: named == null ? null : BaseEncodings.canonicalCodes[named],
        latinText: named == null
            ? table == BaseEncodings.standard
            : _latinTables.contains(named));
    return encoding;
  }

  /// Flattens the `/Differences` array of Table 114 into a code-to-name map.
  ///
  /// "Each code shall be the first index in a sequence of character codes to
  /// be changed. The first character name after the code becomes the name
  /// corresponding to that code. Subsequent names replace consecutive code
  /// indices until the next code appears in the array or the array ends."
  /// Entries are integers and glyph names in any order; the standard forbids
  /// overlapping sequences, and an overlap is reported here.
  static Map<int, String> flattenDifferences(List<Object?> array) {
    final result = <int, String>{};
    var code = -1;
    for (final entry in array) {
      if (entry is int) {
        if (entry < 0 || entry > 255) {
          throw FormatException(
              'A /Differences code must be a byte value, not $entry.');
        }
        code = entry;
      } else if (entry is String) {
        if (code < 0) {
          throw const FormatException(
              'A /Differences array must start with a character code.');
        }
        if (code > 255) {
          throw const FormatException(
              'A /Differences sequence runs past the last character code.');
        }
        if (result.containsKey(code)) {
          throw FormatException(
              'The /Differences sequences overlap at code $code.');
        }
        result[code++] = entry;
      } else {
        throw FormatException(
            'A /Differences array holds only codes and names, not $entry.');
      }
    }
    return result;
  }

  static void fillFontEncoding(FontEncoding encoding) {
    for (int ch = 0; ch < 256; ch++) {
      encoding.unicodeToCode[ch] = ch;
      encoding.codeToUnicode[ch] = ch;
      encoding.unicodeDifferences[ch] = ch;
    }
  }

  String? getBaseEncoding() => baseEncoding;
  bool isFontSpecific() => fontSpecific;

  bool addSymbol(int code, int unicode) {
    if (code < 0 || code > 255) return false;
    String? glyphName = AdobeGlyphList.unicodeToName(unicode);
    if (glyphName != null) {
      unicodeToCode[unicode] = code;
      codeToUnicode[code] = unicode;
      differences[code] = glyphName;
      unicodeDifferences[unicode] = code;
      return true;
    }
    return false;
  }

  int getUnicode(int index) => codeToUnicode[index];

  int getUnicodeDifference(int index) => unicodeDifferences[index] ?? 0;

  bool hasDifferences() {
    if (baseEncoding == PdfEncodings.WINANSI ||
        baseEncoding == PdfEncodings.MACROMAN ||
        baseEncoding == PdfEncodings.PDF_DOC_ENCODING) {
      return false;
    }
    return true;
  }

  String? getDifference(int index) => differences[index];

  /// Assigns the glyph name of one character code, as a `/Differences`
  /// entry does, and keeps the derived Unicode mappings in step with it.
  void setDifference(int index, String difference) {
    if (index < 0 || index > 255) return;
    final previous = differences[index];
    differences[index] = difference;
    if (previous != null) {
      final stale = codeToUnicode[index];
      if (stale > -1 && unicodeToCode[stale] == index) {
        unicodeToCode.remove(stale);
        unicodeDifferences.remove(stale);
      }
      codeToUnicode[index] = -1;
    }
    final unicode = AdobeGlyphList.nameToUnicode(difference);
    if (unicode > -1) {
      codeToUnicode[index] = unicode;
      unicodeToCode[unicode] = index;
      unicodeDifferences[unicode] = index;
    }
  }

  Uint8List convertToBytes(String text) {
    if (text.isEmpty) return Uint8List(0);
    List<int> bytes = [];
    for (int i = 0; i < text.length; i++) {
      int ch = text.codeUnitAt(i);
      if (unicodeToCode.containsKey(ch)) {
        bytes.add(unicodeToCode[ch]!);
      }
    }
    return Uint8List.fromList(bytes);
  }

  Uint8List convertToBytesFromGlyphLine(GlyphLine glyphLine) {
    int bytesCount = glyphLine.size();
    Uint8List result = Uint8List(bytesCount);
    for (int i = 0; i < bytesCount; i++) {
      result[i] = glyphLine.get(i).getCode() & 0xFF;
    }
    return result;
  }

  int convertToByte(int unicode) {
    return unicodeToCode[unicode] ?? 0;
  }

  bool canEncode(int unicode) {
    return unicodeToCode.containsKey(unicode) ||
        TextUtil.isNonPrintable(unicode);
  }

  bool canDecode(int code) {
    return codeToUnicode[code] > -1;
  }

  bool isBuiltWith(String encoding) {
    return normalizeEncoding(encoding) == baseEncoding;
  }

  /// Builds an encoding from this package's own compact notation, which a
  /// caller selects by prefixing the encoding name with `#`.
  ///
  /// The notation exists because 9.6.6 lets a conforming writer choose any
  /// code-to-glyph assignment it likes, and naming one inline is shorter
  /// than composing an encoding dictionary:
  ///
  /// * `#simple <firstCode> <hex> <hex> ...` assigns consecutive codes,
  ///   starting at `firstCode`, to the listed Unicode scalars.
  /// * `#full <code> <glyphName> <hex> ...` assigns each code explicitly;
  ///   a code may be written as a quoted character, as in `'A`.
  ///
  /// Codes and scalars are separated by whitespace or commas.
  void fillCustomEncoding() {
    final source = baseEncoding!.substring(1).trim();
    final tokens = source
        .split(RegExp(r'[\s,]+'))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      throw const FormatException('A custom encoding needs a form and codes.');
    }
    final form = tokens.removeAt(0).toLowerCase();
    if (form == 'full') {
      if (tokens.length % 3 != 0) {
        throw const FormatException(
            'A full custom encoding needs a code, a name and a scalar each.');
      }
      for (var index = 0; index < tokens.length; index += 3) {
        final code = _customCode(tokens[index]);
        final name = tokens[index + 1];
        final unicode = _customScalar(tokens[index + 2]);
        differences[code] = name;
        unicodeToCode[unicode] = code;
        codeToUnicode[code] = unicode;
        unicodeDifferences[unicode] = AdobeGlyphList.nameToUnicode(name);
      }
    } else if (form == 'simple') {
      if (tokens.isEmpty) {
        throw const FormatException(
            'A simple custom encoding needs a first character code.');
      }
      var code = _customCode(tokens.removeAt(0));
      for (final token in tokens) {
        if (code > 255) {
          throw const FormatException(
              'A simple custom encoding runs past the last character code.');
        }
        final unicode = _customScalar(token);
        final name = AdobeGlyphList.unicodeToName(unicode);
        if (name == null) {
          throw FormatException(
              'No glyph name stands for U+${unicode.toRadixString(16)}.');
        }
        differences[code] = name;
        unicodeToCode[unicode] = code;
        codeToUnicode[code] = unicode;
        unicodeDifferences[unicode] = unicode;
        code++;
      }
    } else {
      throw FormatException('Unknown custom encoding form "$form".');
    }
    for (var code = 0; code < 256; code++) {
      differences[code] ??= NOTDEF;
    }
  }

  static int _customCode(String token) {
    final value = token.startsWith("'") && token.length == 2
        ? token.codeUnitAt(1)
        : int.tryParse(token);
    if (value == null || value < 0 || value > 255) {
      throw FormatException('"$token" is not a character code.');
    }
    return value;
  }

  static int _customScalar(String token) {
    final value = int.tryParse(token, radix: 16);
    if (value == null ||
        value < 0 ||
        value > 0x10ffff ||
        (value >= 0xd800 && value <= 0xdfff)) {
      throw FormatException('"$token" is not a Unicode scalar value.');
    }
    return value;
  }

  void fillNamedEncoding() {
    String? enc = baseEncoding;
    if (enc == null) return;

    final named = BaseEncodings.canonicalName(enc);
    if (named != null) {
      final table = BaseEncodings.byName(named)!;
      for (var code = 0; code < 256; code++) {
        differences[code] = table[code];
      }
      _rebuildUnicodeMappings(
          canonical: BaseEncodings.canonicalCodes[named],
          latinText: _latinTables.contains(named));
      fontSpecific = named == BaseEncodings.symbolEncoding ||
          named == BaseEncodings.zapfDingbatsEncoding;
      return;
    }

    // Encodings this package knows only as a byte-to-text conversion, such
    // as the single-byte code pages. Their glyph names come from the list.
    PdfEncodings.convertToBytes(" ", enc); // check existence
    List<int> b = List.generate(256, (i) => i);
    String str = PdfEncodings.convertToString(Uint8List.fromList(b), enc);
    List<int> encoded = str.codeUnits;

    for (int ch = 0; ch < 256; ++ch) {
      int uni = 0;
      if (ch < encoded.length) uni = encoded[ch];

      String? name = AdobeGlyphList.unicodeToName(uni);
      if (name == null) {
        name = NOTDEF;
      } else {
        unicodeToCode[uni] = ch;
        codeToUnicode[ch] = uni;
        unicodeDifferences[uni] = ch;
      }
      differences[ch] = name;
    }
  }

  /// Derives [codeToUnicode], [unicodeToCode] and [unicodeDifferences] from
  /// the glyph names now in [differences].
  ///
  /// When an encoding shows one glyph at several codes, the lowest code wins
  /// unless [canonical] names the code the standard singles out.
  void _rebuildUnicodeMappings(
      {Map<String, int>? canonical, bool latinText = false}) {
    unicodeToCode = {};
    unicodeDifferences = {};
    codeToUnicode = List.filled(256, -1);
    for (var code = 0; code < 256; code++) {
      final name = differences[code];
      if (name == null || name == NOTDEF) continue;
      final unicode = _glyphUnicode(name, latinText);
      if (unicode < 0) continue;
      codeToUnicode[code] = unicode;
      if (!unicodeToCode.containsKey(unicode)) {
        unicodeToCode[unicode] = code;
        unicodeDifferences[unicode] = code;
      }
    }
    canonical?.forEach((name, code) {
      final unicode = _glyphUnicode(name, latinText);
      if (unicode < 0 || differences[code] != name) return;
      unicodeToCode[unicode] = code;
      unicodeDifferences[unicode] = code;
    });
  }

  /// The scalar a Latin-text encoding shows for [name].
  ///
  /// The Adobe Glyph List gives `mu` the Greek letter it denotes in the
  /// Symbol font, but Table D.1 places `mu` at the code Latin text uses for
  /// (U+00B5) MICRO SIGN, so that assignment is restored here.
  static int _glyphUnicode(String name, bool latinText) =>
      latinText && name == 'mu' ? 0xb5 : AdobeGlyphList.nameToUnicode(name);

  /// The encodings of Table D.1 and Table 115, which show Latin text.
  static const Set<String> _latinTables = {
    BaseEncodings.standardEncoding,
    BaseEncodings.winAnsiEncoding,
    BaseEncodings.macRomanEncoding,
    BaseEncodings.pdfDocEncoding,
    BaseEncodings.macOsRomanEncoding,
  };

  static String normalizeEncoding(String? enc) {
    if (enc == null) return "";
    String tmp = enc.toLowerCase();
    if (tmp == "winansi" || tmp == "winansiencoding") {
      return PdfEncodings.WINANSI;
    }
    if (tmp == "macroman" || tmp == "macromanencoding") {
      return PdfEncodings.MACROMAN;
    }
    if (tmp == "zapfdingbatsencoding") return PdfEncodings.ZAPFDINGBATS;
    return enc;
  }
}
