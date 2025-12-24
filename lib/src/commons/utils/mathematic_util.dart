/// Helper class for internal usage only.
///  TODO ? Be aware that its API and functionality may be changed in future.
class MathematicUtil {
  MathematicUtil._();

  /// Rounds a double value using "away from zero" rounding mode.
  /// This matches the Java/C# Math.Round behavior.
  ///
  /// Examples:
  /// - round(2.5) returns 3.0
  /// - round(-2.5) returns -3.0
  /// - round(2.4) returns 2.0
  static double round(double a) {
    // Dart's .round() uses "round half to even" (banker's rounding),
    // but Java/C# use "round half away from zero"
    if (a >= 0) {
      return (a + 0.5).floorToDouble();
    } else {
      return (a - 0.5).ceilToDouble();
    }
  }

  /// Rounds a double to a specific number of decimal places.
  static double roundToDecimal(double value, int decimalPlaces) {
    final multiplier = _pow10(decimalPlaces);
    return round(value * multiplier) / multiplier;
  }

  /// Fast power of 10 calculation.
  static double _pow10(int n) {
    if (n == 0) return 1;
    if (n == 1) return 10;
    if (n == 2) return 100;
    if (n == 3) return 1000;
    if (n == 4) return 10000;
    if (n == 5) return 100000;
    if (n == 6) return 1000000;
    double result = 1;
    for (int i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }
}
