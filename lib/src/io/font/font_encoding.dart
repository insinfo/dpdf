import 'dart:typed_data';
import 'package:dpdf/src/io/font/adobe_glyph_list.dart';
import 'package:dpdf/src/io/font/pdf_encodings.dart';
import 'package:dpdf/src/io/font/otf/glyph_line.dart';

import 'package:dpdf/src/io/util/text_util.dart';

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

  void setDifference(int index, String difference) {
    if (index >= 0 && index < 256) {
      differences[index] = difference;
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

  void fillCustomEncoding() {
    throw UnimplementedError(
        "Custom encoding parsing (starting with #) is not yet implemented.");
  }

  void fillNamedEncoding() {
    String? enc = baseEncoding;
    if (enc == null) return;

    PdfEncodings.convertToBytes(" ", enc); // check existence
    // Note: stdEncoding var is used in C# logic logic for differences array, but here simplified.
    // If I remove stdEncoding, I should fix the warning.

    // Fill base
    List<int> b = List.generate(256, (i) => i);
    String str = PdfEncodings.convertToString(Uint8List.fromList(b), enc);
    List<int> encoded = str.codeUnits;

    for (int ch = 0; ch < 256; ++ch) {
      int uni = 0;
      if (ch < encoded.length) uni = encoded[ch];

      String? name = AdobeGlyphList.unicodeToName(uni);
      if (name == null)
        name = NOTDEF;
      else {
        unicodeToCode[uni] = ch;
        codeToUnicode[ch] = uni;
        unicodeDifferences[uni] = ch;
      }
      differences[ch] = name;
    }
  }

  static String normalizeEncoding(String? enc) {
    if (enc == null) return "";
    String tmp = enc.toLowerCase();
    if (tmp == "winansi" || tmp == "winansiencoding")
      return PdfEncodings.WINANSI;
    if (tmp == "macroman" || tmp == "macromanencoding")
      return PdfEncodings.MACROMAN;
    if (tmp == "zapfdingbatsencoding") return PdfEncodings.ZAPFDINGBATS;
    return enc;
  }
}
