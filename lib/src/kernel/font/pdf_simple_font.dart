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

abstract class PdfSimpleFont<T extends FontProgram> extends PdfFont {
  FontEncoding? fontEncoding;
  bool forceWidthsOutput = false;
  Uint8List usedGlyphs = Uint8List(PdfFont.SIMPLE_FONT_MAX_CHAR_CODE_VALUE + 1);

  // CMapToUnicode toUnicode; // Stubbed for now

  PdfSimpleFont([PdfDictionary? fontDictionary]) : super(fontDictionary) {
    // toUnicode = FontUtil.ProcessToUnicode(fontDictionary.Get(PdfName.ToUnicode));
  }

  @override
  bool isBuiltWith(String fontProgram, String encoding) {
    return getFontProgram()!.isBuiltWith(fontProgram) &&
        (fontEncoding != null && fontEncoding!.isBuiltWith(encoding));
  }

  @override
  GlyphLine createGlyphLine(String content) {
    List<Glyph> glyphs = [];
    if (fontEncoding != null && fontEncoding!.isFontSpecific()) {
      for (int i = 0; i < content.length; i++) {
        Glyph? glyph = fontProgram!.getGlyphByCode(content.codeUnitAt(i));
        if (glyph != null) {
          glyphs.add(glyph);
        }
      }
    } else {
      for (int i = 0; i < content.length; i++) {
        Glyph? glyph = getGlyph(content.codeUnitAt(i));
        if (glyph != null) {
          glyphs.add(glyph);
        }
      }
    }
    return GlyphLine(glyphs);
  }

  @override
  int appendGlyphs(String text, int from, int to, List<Glyph> glyphs) {
    int processed = 0;
    if (fontEncoding != null && fontEncoding!.isFontSpecific()) {
      for (int i = from; i <= to; i++) {
        Glyph? glyph = fontProgram!.getGlyphByCode(text.codeUnitAt(i) & 0xFF);
        if (glyph != null) {
          glyphs.add(glyph);
          processed++;
        } else {
          break;
        }
      }
    } else {
      for (int i = from; i <= to; i++) {
        int ch = text.codeUnitAt(i);
        Glyph? glyph = getGlyph(ch);
        if (glyph != null &&
            (containsGlyph(glyph.getUnicode()) || isAppendableGlyph(glyph))) {
          glyphs.add(glyph);
          processed++;
        } else {
          if (glyph == null && TextUtil.isWhitespaceOrNonPrintable(ch)) {
            processed++;
          } else {
            break;
          }
        }
      }
    }
    return processed;
  }

  @override
  int appendAnyGlyph(String text, int from, List<Glyph> glyphs) {
    Glyph? glyph;
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

  bool isAppendableGlyph(Glyph glyph) {
    return glyph.getCode() > 0 ||
        TextUtil.isWhitespaceOrNonPrintable(glyph.getUnicode());
  }

  FontEncoding? getFontEncoding() => fontEncoding;

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
    } else if (text is GlyphLine) {
      GlyphLine glyphLine = text;
      // Implementation similar to C#
      List<int> bytes = [];
      if (fontEncoding != null && fontEncoding!.isFontSpecific()) {
        for (int i = 0; i < glyphLine.size(); i++) {
          bytes.add(glyphLine.get(i).getCode());
        }
      } else {
        for (int i = 0; i < glyphLine.size(); i++) {
          // if (fontEncoding.canEncode(...))
          // Simplified:
          bytes.add(
              glyphLine.get(i).getUnicode()); // Incorrect logic, needs encoding
        }
      }
      // Use helper
      Uint8List res = Uint8List.fromList(bytes);
      for (int b in res) usedGlyphs[b & 0xFF] = 1;
      return res;
    } else if (text is Glyph) {
      // ...
      return Uint8List(0);
    }
    return Uint8List(0);
  }

  @override
  void writeText(dynamic text, dynamic stream, [int? from, int? to]) {
    if (stream is PdfOutputStream) {
      if (text is String) {
        // WriteEscapedString
        stream.writeBytes(convertToBytes(text));
      } else if (text is GlyphLine) {
        // ...
      }
    }
  }

  // ... rest of implementation (Decode, GetContentWidth) need helper methods.
  @override
  String decode(PdfString content) => "";

  @override
  double getContentWidth(PdfString content) {
    int total = 0;
    Uint8List bytes = content.getValueBytes() ?? Uint8List(0);
    for (int code in bytes) {
      total += getWidth(code);
    }
    return total.toDouble();
  }

  @override
  GlyphLine decodeIntoGlyphLine(PdfString content) {
    return GlyphLine([]);
  }

  // FlushFontData
  void flushFontData(String fontName, PdfName subtype) {
    getPdfObject().put(PdfName.subtype, subtype);
    if (fontName.isNotEmpty) {
      getPdfObject().put(PdfName.baseFont, PdfName(fontName));
    }
    // Fill Widths, FirstChar, LastChar, Encoding, Descriptor
  }

  // BuildWidthsArray
  PdfArray buildWidthsArray(int firstChar, int lastChar) {
    PdfArray wd = PdfArray();
    for (int k = firstChar; k <= lastChar; ++k) {
      if (usedGlyphs[k] == 0) {
        wd.add(PdfNumber(0));
      } else {
        int uni = fontEncoding?.getUnicode(k) ?? -1;
        Glyph? glyph =
            (uni > -1) ? getGlyph(uni) : fontProgram?.getGlyphByCode(k);
        wd.add(PdfNumber((glyph != null ? glyph.getWidth() : 0).toDouble()));
      }
    }
    return wd;
  }

  @override
  PdfDictionary? getFontDescriptor(String fontName) {
    // Implement logic
    return null;
  }

  void setFontProgram(T fontProgram) {
    this.fontProgram = fontProgram;
  }

  void addFontStream(PdfDictionary fontDescriptor);

  bool isBuiltInFont() => false;
}
