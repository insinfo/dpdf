class FontStretches {
  static const int FWIDTH_ULTRA_CONDENSED = 1;
  static const int FWIDTH_EXTRA_CONDENSED = 2;
  static const int FWIDTH_CONDENSED = 3;
  static const int FWIDTH_SEMI_CONDENSED = 4;
  static const int FWIDTH_NORMAL = 5;
  static const int FWIDTH_SEMI_EXPANDED = 6;
  static const int FWIDTH_EXPANDED = 7;
  static const int FWIDTH_EXTRA_EXPANDED = 8;
  static const int FWIDTH_ULTRA_EXPANDED = 9;

  static const String ULTRA_CONDENSED = "UltraCondensed";
  static const String EXTRA_CONDENSED = "ExtraCondensed";
  static const String CONDENSED = "Condensed";
  static const String SEMI_CONDENSED = "SemiCondensed";
  static const String NORMAL = "Normal";
  static const String SEMI_EXPANDED = "SemiExpanded";
  static const String EXPANDED = "Expanded";
  static const String EXTRA_EXPANDED = "ExtraExpanded";
  static const String ULTRA_EXPANDED = "UltraExpanded";

  static String fromOpenTypeWidthClass(int fontWidth) {
    switch (fontWidth) {
      case FWIDTH_ULTRA_CONDENSED:
        return ULTRA_CONDENSED;
      case FWIDTH_EXTRA_CONDENSED:
        return EXTRA_CONDENSED;
      case FWIDTH_CONDENSED:
        return CONDENSED;
      case FWIDTH_SEMI_CONDENSED:
        return SEMI_CONDENSED;
      case FWIDTH_NORMAL:
        return NORMAL;
      case FWIDTH_SEMI_EXPANDED:
        return SEMI_EXPANDED;
      case FWIDTH_EXPANDED:
        return EXPANDED;
      case FWIDTH_EXTRA_EXPANDED:
        return EXTRA_EXPANDED;
      case FWIDTH_ULTRA_EXPANDED:
        return ULTRA_EXPANDED;
      default:
        return NORMAL;
    }
  }
}
