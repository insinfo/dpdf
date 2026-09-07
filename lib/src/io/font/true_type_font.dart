import 'dart:typed_data';

import 'package:dpdf/src/io/font/font_program.dart';
import 'font_metrics.dart';
import 'package:dpdf/src/io/font/otf/glyph.dart';
import 'package:dpdf/src/io/font/open_type_parser.dart';
import 'package:dpdf/src/commons/utils/tuple2.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

class CraftTrueTypeFont extends CraftFontProgram {
  late CraftOpenTypeParser fontParser;
  List<List<int>>? bBoxes;
  bool isVertical = false;
  Map<int, int> kerning = {}; // (first << 16) + second -> value
  Uint8List? fontStreamBytes;

  // Constructors
  CraftTrueTypeFont.fromBytes(Uint8List ttf) {
    fontParser = CraftOpenTypeParser(ttf);
    fontParser.loadTables(true);
    refreshParsedMetrics();
  }

  CraftTrueTypeFont.fromFile(String path) {
    fontParser = CraftOpenTypeParser.fromFile(path);
    fontParser.loadTables(true);
    refreshParsedMetrics();
  }

  // Construct a normalized metrics snapshot before exposing parsed font data.
  void refreshParsedMetrics() {
    final geometry = fontParser.head;
    if (geometry.unitsPerEm <= 0) {
      throw FormatException('Font units-per-em must be positive.');
    }
    final metrics = _normalizedMetrics();
    final bounds = fontParser.readBbox(geometry.unitsPerEm);
    final pairs = fontParser.readKerning(geometry.unitsPerEm);
    final names = fontParser.getFontNames();
    fontMetrics = metrics;
    bBoxes = bounds;
    kerning = pairs;
    fontNames = names;
    fontIdentification.setPanose(fontParser.os_2.panose);
    isFontSpecific = fontParser.cmaps.fontSpecific;
    fillFontGlyphs();
  }

  CraftFontMetrics _normalizedMetrics() {
    final design = fontParser.head;
    final line = fontParser.hhea;
    final windows = fontParser.os_2;
    final decoration = fontParser.post;
    final factor = CraftFontMetrics.UNITS_NORMALIZATION / design.unitsPerEm;
    int scale(int value) => (value * factor).toInt();
    final result = CraftFontMetrics()
      ..unitsPerEm = design.unitsPerEm
      ..normalizationCoef = factor
      ..numOfGlyphs = fontParser.readNumGlyphs()
      ..glyphWidths = List.of(fontParser.getGlyphWidthsByIndex())
      ..bbox = [design.xMin, design.yMin, design.xMax, design.yMax]
          .map(scale)
          .toList()
      ..isFixedPitch = decoration.isFixedPitch
      ..italicAngle = decoration.italicAngle;

    // All lengths entering the PDF font model use the same 1000-unit grid.
    result.ascender = scale(line.Ascender);
    result.descender = scale(line.Descender);
    result.lineGap = scale(line.LineGap);
    result.advanceWidthMax = scale(line.advanceWidthMax);
    result.typoAscender = scale(windows.sTypoAscender);
    result.typoDescender = scale(windows.sTypoDescender);
    result.winAscender = scale(windows.usWinAscent);
    result.winDescender = scale(windows.usWinDescent);
    result.capHeight = scale(windows.sCapHeight);
    result.xHeight = scale(windows.sxHeight);
    result.subscriptOffset = -scale(windows.ySubscriptYOffset);
    result.subscriptSize = scale(windows.ySubscriptYSize);
    result.superscriptOffset = scale(windows.ySuperscriptYOffset);
    result.superscriptSize = scale(windows.ySuperscriptYSize);
    result.strikeoutSize = scale(windows.yStrikeoutSize);
    result.strikeoutPosition = scale(windows.yStrikeoutPosition);
    result.underlineThickness = scale(decoration.underlineThickness);
    result.underlinePosition = scale(decoration.underlinePosition);
    return result;
  }

  void fillFontGlyphs() {
    Map<int, List<int>>? cmap = fontParser.cmaps.cmap31;
    cmap ??= fontParser.cmaps.cmap10;
    cmap ??= fontParser.cmaps.cmap310;
    if (cmap == null && fontParser.cmaps.cmap03 != null) {
      cmap = fontParser.cmaps.cmap03;
    }

    if (cmap != null) {
      cmap.forEach((unicode, entry) {
        int glyphIndex = entry[0];
        int width = entry[1];
        CraftGlyph glyph = CraftGlyph(glyphIndex, width, unicode);
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
    CraftGlyph? g1 = getGlyph(first);
    CraftGlyph? g2 = getGlyph(second);
    if (g1 != null && g2 != null) {
      return getKerningByGlyph(g1, g2);
    }
    return 0;
  }

  @override
  int getKerningByGlyph(CraftGlyph first, CraftGlyph second) {
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
      throw IoException(CraftIoExceptionMessageConstant.ioException);
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
          CraftGlyph? g = getGlyph(k);
          if (g != null) glyphs.add(g.getCode());
        }
      }
    }
  }

  int getDirectoryOffset() => fontParser.directoryOffset;

  Uint8List? readCffFont() => fontParser.readCffFont();
}
