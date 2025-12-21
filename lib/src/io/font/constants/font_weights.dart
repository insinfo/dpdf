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

  static int normalizeFontWeight(int weight) {
    return max(100, min(900, (weight / 100).round() * 100));
  }
}
