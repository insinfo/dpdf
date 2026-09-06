import 'dart:typed_data';
import 'package:pdfcraft/src/io/font/adobe_glyph_list.dart';
import 'package:pdfcraft/src/io/font/pdf_encodings.dart';
import 'package:pdfcraft/src/io/font/otf/glyph_line.dart';

import 'package:pdfcraft/src/io/util/text_util.dart';

class CraftFontEncoding {
  static const String NOTDEF = ".notdef";
  static const String FONT_SPECIFIC = "FontSpecific";

  String? baseEncoding;
  bool fontSpecific = false;

  Map<int, int> unicodeToCode = {};
  List<int> codeToUnicode = List.filled(256, -1);
  List<String?> differences = List.filled(256, null); // Array of strings
  Map<int, int> unicodeDifferences = {};

  CraftFontEncoding() {
    // Default init
  }

  static CraftFontEncoding createFontEncoding(String baseEncoding) {
    CraftFontEncoding encoding = CraftFontEncoding();
    encoding.baseEncoding = normalizeEncoding(baseEncoding);
    if (encoding.baseEncoding!.startsWith("#")) {
      encoding.fillCustomEncoding();
    } else {
      encoding.fillNamedEncoding();
    }
    return encoding;
  }

  static CraftFontEncoding createEmptyFontEncoding() {
    CraftFontEncoding encoding = CraftFontEncoding();
    encoding.baseEncoding = null;
    encoding.fontSpecific = false;
    for (int ch = 0; ch < 256; ch++) {
      encoding.unicodeDifferences[ch] = ch;
    }
    return encoding;
  }

  static CraftFontEncoding createFontSpecificEncoding() {
    CraftFontEncoding encoding = CraftFontEncoding();
    encoding.fontSpecific = true;
    fillFontEncoding(encoding);
    return encoding;
  }

  static void fillFontEncoding(CraftFontEncoding encoding) {
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
    String? glyphName = CraftAdobeGlyphList.unicodeToName(unicode);
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
    if (baseEncoding == CraftPdfEncodings.WINANSI ||
        baseEncoding == CraftPdfEncodings.MACROMAN ||
        baseEncoding == CraftPdfEncodings.PDF_DOC_ENCODING) {
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

  Uint8List convertToBytesFromGlyphLine(CraftGlyphLine glyphLine) {
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
        CraftTextUtil.isNonPrintable(unicode);
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

    CraftPdfEncodings.convertToBytes(" ", enc); // check existence
    // Note: stdEncoding var is used in C# logic logic for differences array, but here simplified.
    // If I remove stdEncoding, I should fix the warning.

    // Fill base
    List<int> b = List.generate(256, (i) => i);
    String str = CraftPdfEncodings.convertToString(Uint8List.fromList(b), enc);
    List<int> encoded = str.codeUnits;

    for (int ch = 0; ch < 256; ++ch) {
      int uni = 0;
      if (ch < encoded.length) uni = encoded[ch];

      String? name = CraftAdobeGlyphList.unicodeToName(uni);
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
      return CraftPdfEncodings.WINANSI;
    if (tmp == "macroman" || tmp == "macromanencoding")
      return CraftPdfEncodings.MACROMAN;
    if (tmp == "zapfdingbatsencoding") return CraftPdfEncodings.ZAPFDINGBATS;
    return enc;
  }
}
