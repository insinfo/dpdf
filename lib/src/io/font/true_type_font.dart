import 'dart:typed_data';

import 'package:dpdf/src/io/font/font_program.dart';
import 'package:dpdf/src/io/font/otf/glyph.dart';
import 'package:dpdf/src/io/font/open_type_parser.dart';
import 'package:dpdf/src/commons/utils/tuple2.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

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

    kerning = fontParser.readKerning(head.unitsPerEm);
    bBoxes = fontParser.readBbox(head.unitsPerEm);

    fontNames = fontParser.getFontNames();

    fontMetrics.setUnitsPerEm(head.unitsPerEm);
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

    fontIdentification.setPanose(os_2.panose);

    // Populate glyphs
    fillFontGlyphs();
  }

  void fillFontGlyphs() {
    Map<int, List<int>>? cmap = fontParser.cmaps.cmap31;
    if (cmap == null) cmap = fontParser.cmaps.cmap10;
    if (cmap == null) cmap = fontParser.cmaps.cmap310;
    if (cmap == null && fontParser.cmaps.cmap03 != null)
      cmap = fontParser.cmaps.cmap03;

    if (cmap != null) {
      cmap.forEach((unicode, entry) {
        int glyphIndex = entry[0];
        int width = entry[1];
        Glyph glyph = Glyph(glyphIndex, width, unicode);
        unicodeToGlyph[unicode] = glyph;
        codeToGlyph[unicode] =
            glyph; // For TrueType, usually same unless distinct encoding
      });
    }

    // Fix space if missing
    fixSpaceIssue();
  }

  @override
  bool hasKernPairs() {
    return kerning.isNotEmpty;
  }

  @override
  int getKerning(int first, int second) {
    Glyph? g1 = getGlyph(first);
    Glyph? g2 = getGlyph(second);
    if (g1 != null && g2 != null) {
      return getKerningByGlyph(g1, g2);
    }
    return 0;
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
      fontStreamBytes = fontParser.getFullFont();
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

  Uint8List getSubset(Iterable<int> glyphs, bool subsetTables) {
    Tuple2<int, Uint8List> res = fontParser.getSubset(glyphs, subsetTables);
    return res.item2;
  }

  void updateUsedGlyphs(
      Set<int> glyphs, bool subset, List<List<int>>? subsetRanges) {
    if (subsetRanges != null) {
      for (var range in subsetRanges) {
        for (int k = range[0]; k <= range[1]; k++) {
          Glyph? g = getGlyph(k);
          if (g != null) glyphs.add(g.getCode());
        }
      }
    }
  }

  int getDirectoryOffset() => fontParser.directoryOffset;
}
