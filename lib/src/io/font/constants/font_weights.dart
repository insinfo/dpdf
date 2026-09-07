import 'dart:math';

class FontWeights {
  static const int THIN = 100;
  static const int EXTRA_LIGHT = 200;
  static const int LIGHT = 300;
  static const int NORMAL = 400;
  static const int MEDIUM = 500;
  static const int SEMI_BOLD = 600;
  static const int BOLD = 700;
  static const int EXTRA_BOLD = 800;
  static const int BLACK = 900;

  static int fromType1FontWeight(String? weight) {
    if (weight == null) return NORMAL;
    String w = weight.toLowerCase();
    if (w.contains("thin")) return THIN;
    if (w.contains("extra") && w.contains("light")) return EXTRA_LIGHT;
    if (w.contains("light")) return LIGHT;
    if (w.contains("medium")) return MEDIUM;
    if (w.contains("demi")) return SEMI_BOLD;
    if (w.contains("semi") && w.contains("bold")) return SEMI_BOLD;
    if (w.contains("extra") && w.contains("bold")) return EXTRA_BOLD;
    if (w.contains("bold")) return BOLD;
    if (w.contains("black")) return BLACK;
    return NORMAL;
  }

  static int normalizeFontWeight(int weight) {
    return max(100, min(900, (weight / 100).round() * 100));
  }
}
