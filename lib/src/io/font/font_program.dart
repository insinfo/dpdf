import 'dart:math';

import 'package:pdfcraft/src/io/font/constants/font_mac_style_flags.dart';
import 'package:pdfcraft/src/io/font/font_identification.dart';
import 'package:pdfcraft/src/io/font/font_metrics.dart';
import 'package:pdfcraft/src/io/font/font_names.dart';
import 'package:pdfcraft/src/io/font/otf/glyph.dart';

abstract class CraftFontProgram {
  static const int HORIZONTAL_SCALING_FACTOR = 100;
  static const int DEFAULT_WIDTH = 1000;
  static const int UNITS_NORMALIZATION = 1000;

  static double convertTextSpaceToGlyphSpace(double value) {
    return value / UNITS_NORMALIZATION;
  }

  static double convertGlyphSpaceToTextSpace(double value) {
    return value * UNITS_NORMALIZATION;
  }

  // codeToGlyph: In case Type1: char code to glyph. In case TrueType: glyph index to glyph.
  Map<int, CraftGlyph> codeToGlyph = {};
  Map<int, CraftGlyph> unicodeToGlyph = {};

  bool isFontSpecific = false;
  CraftFontNames fontNames = CraftFontNames();
  CraftFontMetrics fontMetrics = CraftFontMetrics();
  CraftFontIdentification fontIdentification = CraftFontIdentification();

  int avgWidth = 0;
  String encodingScheme = "FontSpecific"; // FontEncoding.FONT_SPECIFIC
  String? registry;

  int countOfGlyphs() {
    return max(codeToGlyph.length, unicodeToGlyph.length);
  }

  CraftFontNames getFontNames() => fontNames;
  CraftFontMetrics getFontMetrics() => fontMetrics;
  CraftFontIdentification getFontIdentification() => fontIdentification;
  String? characterRegistry() => registry;

  int getPdfFontFlags();

  bool getIsFontSpecific() => isFontSpecific;

  int getWidth(int unicode) {
    CraftGlyph? glyph = getGlyph(unicode);
    return glyph != null ? glyph.getWidth() : 0;
  }

  int getAvgWidth() => avgWidth;

  List<int>? getCharBBox(int unicode) {
    CraftGlyph? glyph = getGlyph(unicode);
    return glyph != null ? glyph.getBbox() : null;
  }

  CraftGlyph? getGlyph(int unicode) {
    return unicodeToGlyph[unicode];
  }

  CraftGlyph? getGlyphByCode(int charCode) {
    return codeToGlyph[charCode];
  }

  bool hasKernPairs() => false;

  int getKerning(int first, int second) {
    CraftGlyph? g1 = unicodeToGlyph[first];
    CraftGlyph? g2 = unicodeToGlyph[second];
    if (g1 != null && g2 != null) {
      return getKerningByGlyph(g1, g2);
    }
    return 0;
  }

  int getKerningByGlyph(CraftGlyph first, CraftGlyph second);

  bool isBuiltWith(String fontName) => false;

  void assignCharacterRegistry(String registry) {
    this.registry = registry;
  }

  static String? trimFontStyle(String? name) {
    if (name == null) return null;
    if (name.endsWith(",Bold")) {
      return name.substring(0, name.length - 5);
    } else if (name.endsWith(",Italic")) {
      return name.substring(0, name.length - 7);
    } else if (name.endsWith(",BoldItalic")) {
      return name.substring(0, name.length - 11);
    } else {
      return name;
    }
  }

  void setTypoAscender(int ascender) {
    fontMetrics.setTypoAscender(ascender);
  }

  void setTypoDescender(int descender) {
    fontMetrics.setTypoDescender(descender);
  }

  void setCapHeight(int capHeight) {
    fontMetrics.setCapHeight(capHeight);
  }

  void setXHeight(int xHeight) {
    fontMetrics.setXHeight(xHeight);
  }

  void setItalicAngle(double italicAngle) {
    fontMetrics.setItalicAngle(italicAngle);
  }

  void setStemV(int stemV) {
    fontMetrics.setStemV(stemV);
  }

  void setStemH(int stemH) {
    fontMetrics.setStemH(stemH);
  }

  void setFontWeight(int fontWeight) {
    fontNames.setFontWeight(fontWeight);
  }

  void setFontStretch(String fontWidth) {
    fontNames.setFontStretch(fontWidth);
  }

  void setFixedPitch(bool isFixedPitch) {
    fontMetrics.setIsFixedPitch(isFixedPitch);
  }

  void setBold(bool isBold) {
    if (isBold) {
      fontNames
          .setMacStyle(fontNames.getMacStyle() | CraftFontMacStyleFlags.BOLD);
    } else {
      fontNames.setMacStyle(
          fontNames.getMacStyle() & (~CraftFontMacStyleFlags.BOLD));
    }
  }

  void setBbox(List<int> bbox) {
    fontMetrics.setBbox(bbox[0], bbox[1], bbox[2], bbox[3]);
  }

  void setFontFamily(String fontFamily) {
    fontNames.setFamilyNameString(fontFamily);
  }

  void setFontName(String fontName) {
    this.fontNames.setFontName(fontName);
    if (this.fontNames.getFullName() == null) {
      this.fontNames.setFullNameString(fontName);
    }
  }

  void fixSpaceIssue() {
    CraftGlyph? space = unicodeToGlyph[32]; // 32 is space
    if (space != null) {
      codeToGlyph[space.getCode()] = space;
    }
  }

  @override
  String toString() {
    String? name = fontNames.getFontName();
    return (name != null && name.isNotEmpty) ? name : super.toString();
  }
}
