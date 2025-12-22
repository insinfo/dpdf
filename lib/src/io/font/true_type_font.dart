import 'dart:typed_data';

import 'package:itext/src/io/font/font_program.dart';
import 'package:itext/src/io/font/otf/glyph.dart';
import 'package:itext/src/io/font/open_type_parser.dart';
import 'package:itext/src/io/exceptions/io_exception.dart';
import 'package:itext/src/io/exceptions/io_exception_message_constant.dart';

class TrueTypeFont extends FontProgram {
  late OpenTypeParser fontParser;
  List<List<int>>? bBoxes;
  bool isVertical = false;
  Map<int, int> kerning = {}; // (first << 16) + second -> value
  Uint8List? fontStreamBytes;

  // Constructors
  TrueTypeFont.fromBytes(Uint8List ttf) {
    fontParser = OpenTypeParser(ttf);
    fontParser.loadTables(true);
    initializeFontProperties();
  }

  TrueTypeFont.fromFile(String path) {
    fontParser = OpenTypeParser.fromFile(path);
    fontParser.loadTables(true);
    initializeFontProperties();
  }

  // Common initialization logic
  void initializeFontProperties() {
    HeaderTable head = fontParser.head;
    HorizontalHeader hhea = fontParser.hhea;
    WindowsMetrics os_2 = fontParser.os_2;
    PostTable post = fontParser.post;

    isFontSpecific = fontParser.cmaps.fontSpecific;

    // TODO: implement readKerning and readBbox in parser
    // kerning = fontParser.readKerning(head.unitsPerEm);
    // bBoxes = fontParser.readBbox(head.unitsPerEm);

    fontNames = fontParser.getFontNames();

    fontMetrics.setUnitsPerEm(head.unitsPerEm);
    // fontMetrics.updateBbox(head.xMin, head.yMin, head.xMax, head.yMax); // updateBbox doesn't exist in Dart FontMetrics yet? Check it.
    fontMetrics.setBbox(head.xMin, head.yMin, head.xMax, head.yMax);

    fontMetrics.setNumberOfGlyphs(fontParser.readNumGlyphs());
    fontMetrics.setGlyphWidths(fontParser.getGlyphWidthsByIndex());
    fontMetrics.setTypoAscender(os_2.sTypoAscender);
    fontMetrics.setTypoDescender(os_2.sTypoDescender);
    fontMetrics.setCapHeight(os_2.sCapHeight);
    fontMetrics.setXHeight(os_2.sxHeight);
    fontMetrics.setItalicAngle(post.italicAngle);
    fontMetrics.setAscender(hhea.Ascender);
    fontMetrics.setDescender(hhea.Descender);
    fontMetrics.setLineGap(hhea.LineGap);
    fontMetrics.setWinAscender(os_2.usWinAscent);
    fontMetrics.setWinDescender(os_2.usWinDescent);
    fontMetrics.setAdvanceWidthMax(hhea.advanceWidthMax);
    fontMetrics.setUnderlinePosition(
        (post.underlinePosition - post.underlineThickness) ~/ 2);
    fontMetrics.setUnderlineThickness(post.underlineThickness);
    fontMetrics.setStrikeoutPosition(os_2.yStrikeoutPosition);
    fontMetrics.setStrikeoutSize(os_2.yStrikeoutSize);
    fontMetrics.setSubscriptOffset(-os_2.ySubscriptYOffset);
    fontMetrics.setSubscriptSize(os_2.ySubscriptYSize);
    fontMetrics.setSuperscriptOffset(os_2.ySuperscriptYOffset);
    fontMetrics.setSuperscriptSize(os_2.ySuperscriptYSize);
    fontMetrics.setIsFixedPitch(post.isFixedPitch);

    // TODO: Font identification and Panose from os_2
  }

  @override
  bool hasKernPairs() {
    return kerning.isNotEmpty;
  }

  @override
  int getKerning(int first, int second) {
    // Override base implementation if needed, or use base if it uses getKerningByGlyph
    // Base implementation in FontProgram uses getKerningByGlyph
    // But TrueTypeFont C# overrides GetKerning(Glyph first, Glyph second)
    // Here we strictly follow Dart method signatures.
    // Wait, FontProgram Dart has: int getKerning(int first, int second);
    // And getKerningByGlyph(Glyph first, Glyph second).

    // We can implement getKerningByGlyph
    // But kerning map is by char code or glyph index?
    // C# says: key is Integer where top 16 bits are glyph number for first char...
    // So it is by glyph index (GID).
    return 0; // TODO implement
  }

  @override
  int getKerningByGlyph(Glyph first, Glyph second) {
    int key = (first.getCode() << 16) + second.getCode();
    return kerning[key] ?? 0;
  }

  bool isCff() {
    return fontParser.cff;
  }

  Uint8List? getFontStreamBytes() {
    if (fontStreamBytes != null) return fontStreamBytes;
    try {
      fontStreamBytes = null; // TODO: Implement getFullFont in parser
      // fontStreamBytes = fontParser.getFullFont();
    } catch (e) {
      throw IoException(IoExceptionMessageConstant.ioException);
    }
    return fontStreamBytes;
  }

  @override
  int getPdfFontFlags() {
    int flags = 0;
    if (fontMetrics.getIsFixedPitch()) {
      flags |= 1;
    }
    flags |= isFontSpecific ? 4 : 32;
    if (fontNames.isItalic()) {
      flags |= 64;
    }
    if (fontNames.isBold() || fontNames.getFontWeight() > 500) {
      flags |= 262144;
    }
    return flags;
  }
}
