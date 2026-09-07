import 'dart:typed_data';

import 'package:dpdf/src/io/font/font_program.dart';
import 'package:dpdf/src/io/font/otf/glyph.dart';
import 'package:dpdf/src/io/font/otf/glyph_line.dart';
import 'package:dpdf/src/io/util/text_util.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

abstract class CraftPdfFont extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  static const int SIMPLE_FONT_MAX_CHAR_CODE_VALUE = 255;
  static final Uint8List EMPTY_BYTES = Uint8List(0);

  CraftFontProgram? fontProgram;
  Map<int, CraftGlyph> notdefGlyphs = {};
  bool newFont = true;
  bool embedded = false;
  bool subset = true;
  List<List<int>>? subsetRanges;

  CraftPdfFont([CraftPdfDictionary? fontDictionary])
      : super(fontDictionary ?? CraftPdfDictionary()) {
    pdfRepresentation().put(CraftPdfName.type, CraftPdfName.font);
  }

  CraftGlyph? getGlyph(int unicode);

  bool containsGlyph(int unicode) {
    CraftGlyph? glyph = getGlyph(unicode);
    if (glyph != null) {
      if (getFontProgram() != null && getFontProgram()!.getIsFontSpecific()) {
        return glyph.getCode() > -1;
      } else {
        return glyph.getCode() > 0;
      }
    }
    return false;
  }

  CraftGlyphLine createGlyphLine(String content);

  int appendGlyphs(String text, int from, int to, List<CraftGlyph> glyphs);

  int appendAnyGlyph(String text, int from, List<CraftGlyph> glyphs);

  Uint8List convertToBytes(dynamic text); // String or GlyphLine or Glyph

  String decode(CraftPdfString content);

  CraftGlyphLine decodeIntoGlyphLine(CraftPdfString characterCodes);

  bool appendDecodedCodesToGlyphsList(
      List<CraftGlyph> list, CraftPdfString characterCodes) {
    return false;
  }

  Future<void> initFromDictionary(CraftPdfDictionary fontDictionary) async {}

  double getContentWidth(CraftPdfString content);

  void writeText(dynamic text, dynamic stream, [int? from, int? to]);

  int getWidth(dynamic text, [double? fontSize]) {
    // Overload dispatch
    if (text is int) {
      int unicode = text;
      if (fontSize == null) {
        CraftGlyph? glyph = getGlyph(unicode);
        return glyph != null ? glyph.getWidth() : 0;
      } else {
        // float GetWidth(int unicode, float fontSize)
        return (CraftFontProgram.convertTextSpaceToGlyphSpace(
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
          if (CraftTextUtil.isSurrogatePair(text, i)) {
            ch = CraftTextUtil.convertToUtf32(text, i);
            i++;
          } else {
            ch = text.codeUnitAt(i);
          }
          CraftGlyph? glyph = getGlyph(ch);
          if (glyph != null) {
            total += glyph.getWidth();
          }
        }
        return total;
      } else {
        return (CraftFontProgram.convertTextSpaceToGlyphSpace(
                getWidth(text) * fontSize))
            .toInt();
      }
    }
    return 0;
  }

  double getWidthPoint(dynamic text, double fontSize) {
    if (text is int) {
      return CraftFontProgram.convertTextSpaceToGlyphSpace(
          getWidth(text) * fontSize);
    } else if (text is String) {
      return CraftFontProgram.convertTextSpaceToGlyphSpace(
          getWidth(text) * fontSize);
    }
    return 0;
  }

  double getDescent(dynamic text, double fontSize) {
    // Simplification: text is string or char code
    int min = 0;
    if (text is int) {
      int unicode = text;
      CraftGlyph? glyph = getGlyph(unicode);
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
        if (CraftTextUtil.isSurrogatePair(text, k)) {
          ch = CraftTextUtil.convertToUtf32(text, k);
          k++;
        } else {
          ch = text.codeUnitAt(k);
        }
        CraftGlyph? glyph = getGlyph(ch);
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
    return CraftFontProgram.convertTextSpaceToGlyphSpace(min * fontSize);
  }

  double getAscent(dynamic text, double fontSize) {
    int max = 0;
    if (text is int) {
      int unicode = text;
      CraftGlyph? glyph = getGlyph(unicode);
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
        if (CraftTextUtil.isSurrogatePair(text, k)) {
          ch = CraftTextUtil.convertToUtf32(text, k);
          k++;
        } else {
          ch = text.codeUnitAt(k);
        }
        CraftGlyph? glyph = getGlyph(ch);
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
    return CraftFontProgram.convertTextSpaceToGlyphSpace(max * fontSize);
  }

  CraftFontProgram? getFontProgram() => fontProgram;

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
  Future<void> flush() async {
    await super.flush();
  }

  CraftPdfDictionary? getFontDescriptor(String fontName);

  @override
  bool requiresIndirectStorage() => true;

  static String updateSubsetPrefix(
      String fontName, bool isSubset, bool isEmbedded) {
    if (isSubset && isEmbedded) {
      //  uses a 6-character random prefix for subsets.
      return "ABCDEF+$fontName";
    }
    return fontName;
  }

  CraftPdfStream? getPdfFontStream(
      Uint8List? fontStreamBytes, List<int>? fontStreamLengths) {
    if (fontStreamBytes == null || fontStreamLengths == null) {
      throw Exception("Font embedding issue");
    }
    CraftPdfStream fontStream = CraftPdfStream.withBytes(fontStreamBytes);
    makeObjectIndirect(fontStream);
    for (int k = 0; k < fontStreamLengths.length; ++k) {
      fontStream.put(CraftPdfName("Length${k + 1}"),
          CraftPdfNumber(fontStreamLengths[k].toDouble()));
    }
    return fontStream;
  }

  bool makeObjectIndirect(CraftPdfObject obj) {
    if (pdfRepresentation().indirectHandle() != null) {
      obj.attachToDocument(
          pdfRepresentation().indirectHandle()!.getDocument()!);
      return true;
    } else {
      return false;
    }
  }

  @override
  String toString() {
    return "PdfFont{fontProgram=$fontProgram}";
  }
}
