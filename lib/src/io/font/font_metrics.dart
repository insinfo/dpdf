class FontMetrics {
  static const int UNITS_NORMALIZATION = 1000;

  double normalizationCoef = 1.0;
  int unitsPerEm = UNITS_NORMALIZATION;
  int numOfGlyphs = 0;
  List<int>? glyphWidths;

  int typoAscender = 800;
  int typoDescender = -200;
  int capHeight = 700;
  int xHeight = 0;
  double italicAngle = 0;
  List<int> bbox = [-50, -200, 1000, 900];

  int ascender = 0;
  int descender = 0;
  int lineGap = 0;
  int winAscender = 0;
  int winDescender = 0;
  int advanceWidthMax = 0;

  int underlinePosition = -100;
  int underlineThickness = 50;

  int strikeoutPosition = 0;
  int strikeoutSize = 0;
  int subscriptSize = 0;
  int subscriptOffset = 0;
  int superscriptSize = 0;
  int superscriptOffset = 0;

  int stemV = 80;
  int stemH = 0;

  bool isFixedPitch = false;

  int getUnitsPerEm() => unitsPerEm;
  int getNumberOfGlyphs() => numOfGlyphs;
  List<int>? getGlyphWidths() => glyphWidths;

  int getTypoAscender() => typoAscender;
  int getTypoDescender() => typoDescender;
  int getCapHeight() => capHeight;
  int getXHeight() => xHeight;
  double getItalicAngle() => italicAngle;
  List<int> getBbox() => bbox;

  void setBbox(int llx, int lly, int urx, int ury) {
    bbox[0] = llx;
    bbox[1] = lly;
    bbox[2] = urx;
    bbox[3] = ury;
  }

  int getAscender() => ascender;
  int getDescender() => descender;
  int getLineGap() => lineGap;
  int getWinAscender() => winAscender;
  int getWinDescender() => winDescender;
  int getAdvanceWidthMax() => advanceWidthMax;

  int getUnderlinePosition() => underlinePosition - underlineThickness ~/ 2;
  int getUnderlineThickness() => underlineThickness;

  int getStrikeoutPosition() => strikeoutPosition;
  int getStrikeoutSize() => strikeoutSize;
  int getSubscriptSize() => subscriptSize;
  int getSubscriptOffset() => subscriptOffset;
  int getSuperscriptSize() => superscriptSize;
  int getSuperscriptOffset() => superscriptOffset;

  int getStemV() => stemV;
  int getStemH() => stemH;

  bool getIsFixedPitch() => isFixedPitch;

  void setUnitsPerEm(int unitsPerEm) {
    this.unitsPerEm = unitsPerEm;
    normalizationCoef = UNITS_NORMALIZATION / unitsPerEm;
  }

  void updateBbox(double llx, double lly, double urx, double ury) {
    bbox[0] = (llx * normalizationCoef).toInt();
    bbox[1] = (lly * normalizationCoef).toInt();
    bbox[2] = (urx * normalizationCoef).toInt();
    bbox[3] = (ury * normalizationCoef).toInt();
  }

  void setNumberOfGlyphs(int numOfGlyphs) => this.numOfGlyphs = numOfGlyphs;
  void setGlyphWidths(List<int> glyphWidths) => this.glyphWidths = glyphWidths;

  void setTypoAscender(int typoAscender) {
    this.typoAscender = (typoAscender * normalizationCoef).toInt();
  }

  void setTypoDescender(int typoDescender) {
    this.typoDescender = (typoDescender * normalizationCoef).toInt();
  }

  void setCapHeight(int capHeight) {
    this.capHeight = (capHeight * normalizationCoef).toInt();
  }

  void setXHeight(int xHeight) {
    this.xHeight = (xHeight * normalizationCoef).toInt();
  }

  void setItalicAngle(double italicAngle) {
    this.italicAngle = italicAngle;
  }

  void setAscender(int ascender) {
    this.ascender = (ascender * normalizationCoef).toInt();
  }

  void setDescender(int descender) {
    this.descender = (descender * normalizationCoef).toInt();
  }

  void setLineGap(int lineGap) {
    this.lineGap = (lineGap * normalizationCoef).toInt();
  }

  void setWinAscender(int winAscender) {
    this.winAscender = (winAscender * normalizationCoef).toInt();
  }

  void setWinDescender(int winDescender) {
    this.winDescender = (winDescender * normalizationCoef).toInt();
  }

  void setAdvanceWidthMax(int advanceWidthMax) {
    this.advanceWidthMax = (advanceWidthMax * normalizationCoef).toInt();
  }

  void setUnderlinePosition(int underlinePosition) {
    this.underlinePosition = (underlinePosition * normalizationCoef).toInt();
  }

  void setUnderlineThickness(int underlineThickness) {
    this.underlineThickness = underlineThickness;
  }

  void setSubscriptSize(int subscriptSize) {
    this.subscriptSize = (subscriptSize * normalizationCoef).toInt();
  }

  void setSubscriptOffset(int subscriptOffset) {
    this.subscriptOffset = (subscriptOffset * normalizationCoef).toInt();
  }

  void setSuperscriptSize(int superscriptSize) {
    this.superscriptSize = superscriptSize;
  }

  void setSuperscriptOffset(int superscriptOffset) {
    this.superscriptOffset = (superscriptOffset * normalizationCoef).toInt();
  }

  void setStemV(int stemV) {
    this.stemV = stemV;
  }

  void setStemH(int stemH) {
    this.stemH = stemH;
  }

  void setIsFixedPitch(bool isFixedPitch) {
    this.isFixedPitch = isFixedPitch;
  }
}
