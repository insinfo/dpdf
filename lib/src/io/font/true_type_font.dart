import 'dart:typed_data';

import 'package:dpdf/src/io/font/adobe_glyph_list.dart';
import 'package:dpdf/src/io/font/base_encodings.dart';
import 'package:dpdf/src/io/font/font_program.dart';
import 'font_metrics.dart';
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
    refreshParsedMetrics();
  }

  /// Opens the font whose table directory starts at [directoryOffset] of the
  /// font collection [ttc].
  ///
  /// Nothing is copied out of [ttc]: the parser reads the tables where they
  /// lie, which is what lets two fonts of the collection share them. Because
  /// the file is then not this font's own program, [standaloneSfnt] supplies
  /// the bytes a PDF font stream should embed; it is only called if they are
  /// asked for. [TrueTypeCollection] is the usual caller.
  TrueTypeFont.fromCollection(Uint8List ttc, int directoryOffset,
      {int index = -1, Uint8List Function()? standaloneSfnt}) {
    fontParser = OpenTypeParser.atOffset(ttc, directoryOffset, ttcIndex: index);
    fontParser.fullFontSource = standaloneSfnt;
    fontParser.loadTables(true);
    refreshParsedMetrics();
  }

  TrueTypeFont.fromFile(String path) {
    fontParser = OpenTypeParser.fromFile(path);
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

  FontMetrics _normalizedMetrics() {
    final design = fontParser.head;
    final line = fontParser.hhea;
    final windows = fontParser.os_2;
    final decoration = fontParser.post;
    final factor = FontMetrics.UNITS_NORMALIZATION / design.unitsPerEm;
    int scale(int value) => (value * factor).toInt();
    final result = FontMetrics()
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

  /// The glyph a symbolic font shows for the single byte [code].
  ///
  /// ISO 32000-1:2008, 9.6.6.4: when a font has no `/Encoding` entry or its
  /// descriptor sets the Symbolic flag, "if the font contains a (3, 0)
  /// subtable, the range of character codes shall be one of these:
  /// 0x0000 - 0x00FF, 0xF000 - 0xF0FF, 0xF100 - 0xF1FF, or 0xF200 - 0xF2FF.
  /// Depending on the range of codes, each byte from the string shall be
  /// prepended with the high byte of the range". Otherwise the byte reaches
  /// a (1, 0) subtable unchanged.
  Glyph? getGlyphBySymbolicCode(int code) {
    if (code < 0 || code > 0xff) return null;
    final symbolic = fontParser.cmaps.symbolic;
    if (symbolic != null) {
      for (final page in const [0x0000, 0xf000, 0xf100, 0xf200]) {
        final entry = symbolic[page | code];
        if (entry != null) return _glyphOf(entry, code);
      }
    }
    final macRoman = fontParser.cmaps.macRoman;
    final entry = macRoman?[code];
    return entry == null ? null : _glyphOf(entry, code);
  }

  /// The glyph this program stores under [glyphName].
  ///
  /// ISO 32000-1:2008, 9.6.6.4 reaches a TrueType glyph from a name in
  /// three steps, each tried in turn: through the Adobe Glyph List and a
  /// (3, 1) subtable; through the Mac OS Roman encoding of Table 115 and a
  /// (1, 0) subtable; and finally through the "post" table, which is the
  /// only one of the three that stores names itself.
  Glyph? getGlyphByName(String glyphName) {
    final unicode = AdobeGlyphList.nameToUnicode(glyphName);
    if (unicode > -1) {
      final entry = fontParser.cmaps.cmap31?[unicode];
      if (entry != null) return _glyphOf(entry, unicode);
    }
    final macRomanCode = BaseEncodings.macOsRomanCode(glyphName);
    if (macRomanCode != null) {
      final entry = fontParser.cmaps.macRoman?[macRomanCode];
      if (entry != null) return _glyphOf(entry, unicode);
    }
    final glyphIndex = fontParser.postGlyphIndex(glyphName);
    if (glyphIndex == null) return null;
    return Glyph(glyphIndex, fontParser.getGlyphWidth(glyphIndex), unicode);
  }

  Glyph _glyphOf(List<int> cmapEntry, int unicode) =>
      Glyph(cmapEntry[0], cmapEntry[1], unicode);

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

  /// The position this font holds in the collection it came from, or -1 when
  /// it was read from a file that holds a single font.
  int getCollectionIndex() => fontParser.ttcIndex;

  Uint8List? readCffFont() => fontParser.readCffFont();
}
