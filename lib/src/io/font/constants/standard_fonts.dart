class StandardFonts {
  static const String COURIER = "Courier";
  static const String COURIER_BOLD = "Courier-Bold";
  static const String COURIER_OBLIQUE = "Courier-Oblique";
  static const String COURIER_BOLD_OBLIQUE = "Courier-BoldOblique";
  static const String HELVETICA = "Helvetica";
  static const String HELVETICA_BOLD = "Helvetica-Bold";
  static const String HELVETICA_OBLIQUE = "Helvetica-Oblique";
  static const String HELVETICA_BOLD_OBLIQUE = "Helvetica-BoldOblique";
  static const String SYMBOL = "Symbol";
  static const String TIMES_ROMAN = "Times-Roman";
  static const String TIMES_BOLD = "Times-Bold";
  static const String TIMES_ITALIC = "Times-Italic";
  static const String TIMES_BOLD_ITALIC = "Times-BoldItalic";
  static const String ZAPFDINGBATS = "ZapfDingbats";

  static final Set<String> _standardFonts = {
    COURIER,
    COURIER_BOLD,
    COURIER_OBLIQUE,
    COURIER_BOLD_OBLIQUE,
    HELVETICA,
    HELVETICA_BOLD,
    HELVETICA_OBLIQUE,
    HELVETICA_BOLD_OBLIQUE,
    SYMBOL,
    TIMES_ROMAN,
    TIMES_BOLD,
    TIMES_ITALIC,
    TIMES_BOLD_ITALIC,
    ZAPFDINGBATS
  };

  static bool isStandardFont(String fontName) {
    return _standardFonts.contains(fontName);
  }
}
