import 'dart:typed_data';

import 'package:itext/src/io/font/font_program.dart';
import 'package:itext/src/io/font/otf/glyph.dart';
import 'package:itext/src/io/font/otf/glyph_line.dart';
import 'package:itext/src/io/util/text_util.dart';
import 'package:itext/src/kernel/pdf/pdf_dictionary.dart';
import 'package:itext/src/kernel/pdf/pdf_name.dart';
import 'package:itext/src/kernel/pdf/pdf_number.dart';
import 'package:itext/src/kernel/pdf/pdf_object.dart';
import 'package:itext/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:itext/src/kernel/pdf/pdf_stream.dart';
import 'package:itext/src/kernel/pdf/pdf_string.dart';

abstract class PdfFont extends PdfObjectWrapper<PdfDictionary> {
  static const int SIMPLE_FONT_MAX_CHAR_CODE_VALUE = 255;
  static final Uint8List EMPTY_BYTES = Uint8List(0);

  FontProgram? fontProgram;
  Map<int, Glyph> notdefGlyphs = {};
  bool newFont = true;
  bool embedded = false;
  bool subset = true;
  List<List<int>>? subsetRanges;

  PdfFont([PdfDictionary? fontDictionary])
      : super(fontDictionary ?? PdfDictionary()) {
    getPdfObject().put(PdfName.type, PdfName.font);
  }

  Glyph? getGlyph(int unicode);

  bool containsGlyph(int unicode) {
    Glyph? glyph = getGlyph(unicode);
    if (glyph != null) {
      if (getFontProgram() != null && getFontProgram()!.getIsFontSpecific()) {
        return glyph.getCode() > -1;
      } else {
        return glyph.getCode() > 0;
      }
    }
    return false;
  }

  GlyphLine createGlyphLine(String content);

  int appendGlyphs(String text, int from, int to, List<Glyph> glyphs);

  int appendAnyGlyph(String text, int from, List<Glyph> glyphs);

  Uint8List convertToBytes(dynamic text); // String or GlyphLine or Glyph

  String decode(PdfString content);

  GlyphLine decodeIntoGlyphLine(PdfString characterCodes);

  bool appendDecodedCodesToGlyphsList(
      List<Glyph> list, PdfString characterCodes) {
    return false;
  }

  double getContentWidth(PdfString content);

  void writeText(dynamic text, dynamic stream, [int? from, int? to]);

  int getWidth(dynamic text, [double? fontSize]) {
    // Overload dispatch
    if (text is int) {
      int unicode = text;
      if (fontSize == null) {
        Glyph? glyph = getGlyph(unicode);
        return glyph != null ? glyph.getWidth() : 0;
      } else {
        // float GetWidth(int unicode, float fontSize)
        return (FontProgram.convertTextSpaceToGlyphSpace(
                getWidth(unicode) * fontSize))
            .toInt();
        // Wait, C# returns float, logic: value / 1000 * size.
        // My `convertTextSpaceToGlyphSpace` return double.
      }
    } else if (text is String) {
      if (fontSize == null) {
        int total = 0;
        for (int i = 0; i < text.length; i++) {
          int ch;
          if (TextUtil.isSurrogatePair(text, i)) {
            ch = TextUtil.convertToUtf32(text, i);
            i++;
          } else {
            ch = text.codeUnitAt(i);
          }
          Glyph? glyph = getGlyph(ch);
          if (glyph != null) {
            total += glyph.getWidth();
          }
        }
        return total;
      } else {
        return (FontProgram.convertTextSpaceToGlyphSpace(
                getWidth(text) * fontSize))
            .toInt();
      }
    }
    return 0;
  }

  double getWidthPoint(dynamic text, double fontSize) {
    if (text is int) {
      return FontProgram.convertTextSpaceToGlyphSpace(
          getWidth(text) * fontSize);
    } else if (text is String) {
      return FontProgram.convertTextSpaceToGlyphSpace(
          getWidth(text) * fontSize);
    }
    return 0;
  }

  double getDescent(dynamic text, double fontSize) {
    // Simplification: text is string or char code
    int min = 0;
    if (text is int) {
      int unicode = text;
      Glyph? glyph = getGlyph(unicode);
      if (glyph == null) return 0;
      List<int>? bbox = glyph.getBbox();
      if (bbox != null && bbox[1] < min) {
        min = bbox[1];
      } else if (bbox == null &&
          getFontProgram()!.getFontMetrics().getTypoDescender() < min) {
        min = getFontProgram()!.getFontMetrics().getTypoDescender();
      }
    } else if (text is String) {
      for (int k = 0; k < text.length; ++k) {
        int ch;
        if (TextUtil.isSurrogatePair(text, k)) {
          ch = TextUtil.convertToUtf32(text, k);
          k++;
        } else {
          ch = text.codeUnitAt(k);
        }
        Glyph? glyph = getGlyph(ch);
        if (glyph != null) {
          List<int>? bbox = glyph.getBbox();
          if (bbox != null && bbox[1] < min) {
            min = bbox[1];
          } else if (bbox == null &&
              getFontProgram()!.getFontMetrics().getTypoDescender() < min) {
            min = getFontProgram()!.getFontMetrics().getTypoDescender();
          }
        }
      }
    }
    return FontProgram.convertTextSpaceToGlyphSpace(min * fontSize);
  }

  double getAscent(dynamic text, double fontSize) {
    int max = 0;
    if (text is int) {
      int unicode = text;
      Glyph? glyph = getGlyph(unicode);
      if (glyph == null) return 0;
      List<int>? bbox = glyph.getBbox();
      if (bbox != null && bbox[3] > max) {
        max = bbox[3];
      } else if (bbox == null &&
          getFontProgram()!.getFontMetrics().getTypoAscender() > max) {
        max = getFontProgram()!.getFontMetrics().getTypoAscender();
      }
    } else if (text is String) {
      for (int k = 0; k < text.length; ++k) {
        int ch;
        if (TextUtil.isSurrogatePair(text, k)) {
          ch = TextUtil.convertToUtf32(text, k);
          k++;
        } else {
          ch = text.codeUnitAt(k);
        }
        Glyph? glyph = getGlyph(ch);
        if (glyph != null) {
          List<int>? bbox = glyph.getBbox();
          if (bbox != null && bbox[3] > max) {
            max = bbox[3];
          } else if (bbox == null &&
              getFontProgram()!.getFontMetrics().getTypoAscender() > max) {
            max = getFontProgram()!.getFontMetrics().getTypoAscender();
          }
        }
      }
    }
    return FontProgram.convertTextSpaceToGlyphSpace(max * fontSize);
  }

  FontProgram? getFontProgram() => fontProgram;

  bool isEmbedded() => embedded;
  bool isSubset() => subset;
  void setSubset(bool subset) => this.subset = subset;

  void addSubsetRange(List<int> range) {
    subsetRanges ??= [];
    subsetRanges!.add(range);
    setSubset(true);
  }

  bool isBuiltWith(String fontProgram, String encoding) => false;

  @override
  void flush() {
    super.flush();
  }

  PdfDictionary? getFontDescriptor(String fontName);

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  static String updateSubsetPrefix(
      String fontName, bool isSubset, bool isEmbedded) {
    if (isSubset && isEmbedded) {
      // TODO: AddRandomSubsetPrefix
      return "AAAAAA+" + fontName;
    }
    return fontName;
  }

  PdfStream? getPdfFontStream(
      Uint8List? fontStreamBytes, List<int>? fontStreamLengths) {
    if (fontStreamBytes == null || fontStreamLengths == null) {
      throw Exception("Font embedding issue");
    }
    PdfStream fontStream = PdfStream.withBytes(fontStreamBytes);
    makeObjectIndirect(fontStream);
    for (int k = 0; k < fontStreamLengths.length; ++k) {
      fontStream.put(PdfName("Length${k + 1}"),
          PdfNumber(fontStreamLengths[k].toDouble()));
    }
    return fontStream;
  }

  bool makeObjectIndirect(PdfObject obj) {
    if (getPdfObject().getIndirectReference() != null) {
      obj.makeIndirect(getPdfObject().getIndirectReference()!.getDocument()!);
      return true;
    } else {
      // markObjectAsIndirect(obj); // TODO: Implement if needed in PdfObjectWrapper or PdfObject
      return false;
    }
  }

  @override
  String toString() {
    return "PdfFont{fontProgram=$fontProgram}";
  }
}
