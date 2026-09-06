import 'gf_256_poly.dart';

/// This class contains utility methods for performing mathematical operations over
/// the Galois Field GF(256).
class GF256 {
  // x^8 + x^4 + x^3 + x^2 + 1
  static final GF256 QR_CODE_FIELD = GF256._(0x011D);

  // x^8 + x^5 + x^3 + x^2 + 1
  static final GF256 DATA_MATRIX_FIELD = GF256._(0x012D);

  late List<int> _expTable;
  late List<int> _logTable;
  late GF256Poly _zero;
  late GF256Poly _one;

  GF256._(int primitive) {
    _expTable = List<int>.filled(256, 0);
    _logTable = List<int>.filled(256, 0);
    int x = 1;
    for (int i = 0; i < 256; i++) {
      _expTable[i] = x;
      // x = x * 2; we're assuming the generator alpha is 2
      x <<= 1;
      if (x >= 0x100) {
        x ^= primitive;
      }
    }
    for (int i = 0; i < 255; i++) {
      _logTable[_expTable[i]] = i;
    }
    // logTable[0] == 0 but this should never be used
    _zero = GF256Poly(this, [0]);
    _one = GF256Poly(this, [1]);
  }

  GF256Poly getZero() {
    return _zero;
  }

  GF256Poly getOne() {
    return _one;
  }

  /// Returns the monomial representing coefficient * x^degree
  GF256Poly buildMonomial(int degree, int coefficient) {
    if (degree < 0) {
      throw ArgumentError();
    }
    if (coefficient == 0) {
      return _zero;
    }
    List<int> coefficients = List<int>.filled(degree + 1, 0);
    coefficients[0] = coefficient;
    return GF256Poly(this, coefficients);
  }

  /// Implements both addition and subtraction -- they are the same in GF(256).
  /// Returns sum/difference of a and b
  static int addOrSubtract(int a, int b) {
    return a ^ b;
  }

  /// Returns 2 to the power of a in GF(256)
  int exp(int a) {
    return _expTable[a];
  }

  /// Returns base 2 log of a in GF(256)
  int log(int a) {
    if (a == 0) {
      throw ArgumentError();
    }
    return _logTable[a];
  }

  /// Returns multiplicative inverse of a
  int inverse(int a) {
    if (a == 0) {
      throw Exception(
          "ArithmeticException"); // Dart doesn't have ArithmeticException
    }
    return _expTable[255 - _logTable[a]];
  }

  /// Returns product of a and b in GF(256)
  int multiply(int a, int b) {
    if (a == 0 || b == 0) {
      return 0;
    }
    if (a == 1) {
      return b;
    }
    if (b == 1) {
      return a;
    }
    return _expTable[(_logTable[a] + _logTable[b]) % 255];
  }
}
