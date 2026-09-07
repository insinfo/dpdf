import 'dart:typed_data';

import 'package:dpdf/src/io/font/font_encoding.dart';
import 'package:dpdf/src/io/font/font_program.dart';
import 'package:dpdf/src/io/font/otf/glyph.dart';
import 'package:dpdf/src/io/font/otf/glyph_line.dart';
import 'package:dpdf/src/io/util/text_util.dart';
import 'package:dpdf/src/kernel/font/pdf_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_output_stream.dart';

abstract class CraftPdfSimpleFont<T extends CraftFontProgram>
    extends CraftPdfFont {
  CraftFontEncoding? fontEncoding;
  bool forceWidthsOutput = false;
  Uint8List usedGlyphs =
      Uint8List(CraftPdfFont.SIMPLE_FONT_MAX_CHAR_CODE_VALUE + 1);

  // CMapToUnicode toUnicode; // Stubbed for now

  CraftPdfSimpleFont([super.fontDictionary]) {
    // toUnicode = FontUtil.ProcessToUnicode(fontDictionary.Get(PdfName.ToUnicode));
  }

  @override
  bool isBuiltWith(String fontProgram, String encoding) {
    return getFontProgram()!.isBuiltWith(fontProgram) &&
        (fontEncoding != null && fontEncoding!.isBuiltWith(encoding));
  }

  @override
  CraftGlyphLine createGlyphLine(String content) {
    List<CraftGlyph> glyphs = [];
    if (fontEncoding != null && fontEncoding!.isFontSpecific()) {
      for (int i = 0; i < content.length; i++) {
        CraftGlyph? glyph = fontProgram!.getGlyphByCode(content.codeUnitAt(i));
        if (glyph != null) {
          glyphs.add(glyph);
        }
      }
    } else {
      for (int i = 0; i < content.length; i++) {
        CraftGlyph? glyph = getGlyph(content.codeUnitAt(i));
        if (glyph != null) {
          glyphs.add(glyph);
        }
      }
    }
    return CraftGlyphLine(glyphs);
  }

  @override
  int appendGlyphs(String text, int from, int to, List<CraftGlyph> glyphs) {
    if (from > to) return 0;
    RangeError.checkValidRange(from, to + 1, text.length);
    final rawCodes = fontEncoding?.isFontSpecific() ?? false;
    var cursor = from;
    while (cursor <= to) {
      var scalar = text.codeUnitAt(cursor);
      var units = 1;
      if (!rawCodes && scalar >= 0xd800 && scalar <= 0xdbff && cursor < to) {
        final low = text.codeUnitAt(cursor + 1);
        if (low >= 0xdc00 && low <= 0xdfff) {
          scalar = 0x10000 + (scalar - 0xd800) * 1024 + low - 0xdc00;
          units = 2;
        }
      }
      final glyph = rawCodes
          ? fontProgram!.getGlyphByCode(scalar & 255)
          : getGlyph(scalar);
      if (glyph == null) {
        if (rawCodes || !CraftTextUtil.isWhitespaceOrNonPrintable(scalar)) {
          break;
        }
      } else {
        if (!rawCodes &&
            !containsGlyph(glyph.getUnicode()) &&
            !isAppendableGlyph(glyph)) {
          break;
        }
        glyphs.add(glyph);
      }
      cursor += units;
    }
    return cursor - from;
  }

  @override
  int appendAnyGlyph(String text, int from, List<CraftGlyph> glyphs) {
    CraftGlyph? glyph;
    if (fontEncoding != null && fontEncoding!.isFontSpecific()) {
      glyph = fontProgram!.getGlyphByCode(text.codeUnitAt(from));
    } else {
      glyph = getGlyph(text.codeUnitAt(from));
    }
    if (glyph != null) {
      glyphs.add(glyph);
    }
    return 1;
  }

  bool isAppendableGlyph(CraftGlyph glyph) {
    return glyph.getCode() > 0 ||
        CraftTextUtil.isWhitespaceOrNonPrintable(glyph.getUnicode());
  }

  CraftFontEncoding? getFontEncoding() => fontEncoding;

  // CMapToUnicode getToUnicode() => toUnicode;

  @override
  Uint8List convertToBytes(dynamic text) {
    if (text is String) {
      Uint8List bytes;
      if (fontEncoding == null) {
        bytes = Uint8List.fromList(text.codeUnits); // fallback
      } else {
        bytes = fontEncoding!.convertToBytes(text);
      }

      for (int b in bytes) {
        usedGlyphs[b & 0xff] = 1;
      }
      return bytes;
    } else if (text is CraftGlyphLine) {
      CraftGlyphLine glyphLine = text;
      Uint8List res = Uint8List(glyphLine.size());
      for (int i = 0; i < glyphLine.size(); i++) {
        final glyph = glyphLine.get(i);
        int code;
        if (fontEncoding == null) {
          code = glyph.getCode();
        } else if (fontEncoding!.isFontSpecific()) {
          code = glyph.getCode();
        } else {
          int uni = glyph.getUnicode();
          code = fontEncoding!.convertToByte(uni);
          if (code == 0 && uni > 0) {
            // Unmapped char? Fallback to glyph's own code if valid
            code = glyph.getCode();
          }
        }
        res[i] = code & 0xFF;
        usedGlyphs[res[i]] = 1;
      }
      return res;
    }
    return Uint8List(0);
  }

  @override
  void writeText(dynamic text, dynamic stream, [int? from, int? to]) {
    if (stream is CraftPdfOutputStream) {
      Uint8List bytes;
      if (text is String) {
        bytes = convertToBytes(text);
      } else if (text is CraftGlyphLine) {
        bytes = convertToBytes(text);
      } else {
        return;
      }

      stream.writeByte(40); // (
      for (int b in bytes) {
        // Essential PDF string escaping: ( ) \
        if (b == 40 || b == 41 || b == 92) {
          stream.writeByte(92); // \
        }
        stream.writeByte(b);
      }
      stream.writeByte(41); // )
    }
  }

  @override
  String decode(CraftPdfString content) {
    Uint8List bytes = content.getValueBytes() ?? Uint8List(0);
    StringBuffer sb = StringBuffer();
    for (int b in bytes) {
      int uni = fontEncoding?.getUnicode(b & 0xFF) ?? -1;
      if (uni != -1) {
        sb.writeCharCode(uni);
      } else {
        sb.writeCharCode(b); // Fallback
      }
    }
    return sb.toString();
  }

  @override
  CraftGlyphLine decodeIntoGlyphLine(CraftPdfString content) {
    Uint8List bytes = content.getValueBytes() ?? Uint8List(0);
    List<CraftGlyph> glyphs = [];
    for (int b in bytes) {
      int uni = fontEncoding?.getUnicode(b & 0xFF) ?? -1;
      CraftGlyph glyph = getFontProgram()?.getGlyphByCode(b & 0xFF) ??
          CraftGlyph(b & 0xFF, 0, uni);
      glyphs.add(glyph);
    }
    return CraftGlyphLine(glyphs);
  }

  @override
  double getContentWidth(CraftPdfString content) {
    int total = 0;
    Uint8List bytes = content.getValueBytes() ?? Uint8List(0);
    for (int code in bytes) {
      total += getWidth(code);
    }
    return total.toDouble();
  }

  // FlushFontData
  Future<void> flushFontData(String fontName, CraftPdfName subtype) async {
    final dict = pdfRepresentation();
    dict.put(CraftPdfName.subtype, subtype);
    dict.put(CraftPdfName.baseFont, CraftPdfName(fontName));

    if (fontEncoding != null) {
      if (fontEncoding!.getBaseEncoding() != null &&
          fontEncoding!.getBaseEncoding()!.isNotEmpty) {
        String base = fontEncoding!.getBaseEncoding()!;
        if (base == "Windows-1252") {
          dict.put(CraftPdfName.encoding, CraftPdfName.winAnsiEncoding);
        } else if (base == "MacRoman") {
          dict.put(CraftPdfName.encoding, CraftPdfName.macRomanEncoding);
        } else {
          dict.put(CraftPdfName.encoding, CraftPdfName(base));
        }
      }

      if (fontEncoding!.hasDifferences()) {
        CraftPdfDictionary enc = CraftPdfDictionary();
        String? base = fontEncoding!.getBaseEncoding();
        if (base != null && base.isNotEmpty) {
          if (base == "Windows-1252") {
            enc.put(CraftPdfName.baseEncoding, CraftPdfName.winAnsiEncoding);
          } else if (base == "MacRoman") {
            enc.put(CraftPdfName.baseEncoding, CraftPdfName.macRomanEncoding);
          } else {
            enc.put(CraftPdfName.baseEncoding, CraftPdfName(base));
          }
        }

        CraftPdfArray diffs = CraftPdfArray();
        int last = -2;
        bool hasDiffs = false;
        for (int i = 0; i < 256; i++) {
          String? name = fontEncoding!.getDifference(i);
          if (name != null && name != ".notdef") {
            if (i != last + 1) {
              diffs.add(CraftPdfNumber(i.toDouble()));
            }
            diffs.add(CraftPdfName(name));
            last = i;
            hasDiffs = true;
          }
        }
        if (hasDiffs) {
          enc.put(CraftPdfName.type, CraftPdfName.intern('Encoding'));
          enc.put(CraftPdfName.differences, diffs);
          dict.put(CraftPdfName.encoding, enc);
        }
      }
    }

    int firstChar = 255;
    int lastChar = 0;
    bool charsUsed = false;
    for (int i = 0; i < usedGlyphs.length; i++) {
      if (usedGlyphs[i] != 0) {
        if (i < firstChar) firstChar = i;
        if (i > lastChar) lastChar = i;
        charsUsed = true;
      }
    }

    if (charsUsed) {
      dict.put(CraftPdfName.firstChar, CraftPdfNumber(firstChar.toDouble()));
      dict.put(CraftPdfName.lastChar, CraftPdfNumber(lastChar.toDouble()));
      dict.put(CraftPdfName.widths, buildWidthsArray(firstChar, lastChar));
    }

    CraftPdfDictionary? descriptor = getFontDescriptor(fontName);
    if (descriptor != null) {
      dict.put(CraftPdfName.fontDescriptor, descriptor);
      makeObjectIndirect(descriptor);
      await addFontStream(descriptor);
    }
  }

  // BuildWidthsArray
  CraftPdfArray buildWidthsArray(int firstChar, int lastChar) {
    CraftPdfArray wd = CraftPdfArray();
    for (int k = firstChar; k <= lastChar; ++k) {
      if (usedGlyphs[k] == 0) {
        wd.add(CraftPdfNumber(0));
      } else {
        int uni = fontEncoding?.getUnicode(k) ?? -1;
        CraftGlyph? glyph =
            (uni > -1) ? getGlyph(uni) : fontProgram?.getGlyphByCode(k);
        wd.add(
            CraftPdfNumber((glyph != null ? glyph.getWidth() : 0).toDouble()));
      }
    }
    return wd;
  }

  @override
  CraftPdfDictionary? getFontDescriptor(String fontName) {
    // Implement logic
    return null;
  }

  void setFontProgram(T fontProgram) {
    this.fontProgram = fontProgram;
  }

  Future<void> addFontStream(CraftPdfDictionary fontDescriptor);

  bool isBuiltInFont() => false;
}
