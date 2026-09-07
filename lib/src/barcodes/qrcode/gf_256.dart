import 'gf_256_poly.dart';

/// Byte-polynomial arithmetic using reduction modulo an irreducible polynomial.
/// Multiplication operates on bits rather than using logarithm tables.
class GF256 {
  static final GF256 QR_CODE_FIELD = GF256._(0x11d);
  static final GF256 DATA_MATRIX_FIELD = GF256._(0x12d);
  final int _modulus;
  late final GF256Poly _zero = GF256Poly(this, [0]);
  late final GF256Poly _one = GF256Poly(this, [1]);

  GF256._(this._modulus);
  GF256Poly getZero() => _zero;
  GF256Poly getOne() => _one;

  GF256Poly buildMonomial(int degree, int coefficient) {
    RangeError.checkNotNegative(degree, 'degree');
    _checkByte(coefficient);
    return coefficient == 0
        ? _zero
        : GF256Poly(this, [coefficient, ...List<int>.filled(degree, 0)]);
  }

  static int addOrSubtract(int a, int b) => a ^ b;

  int multiply(int a, int b) {
    _checkByte(a);
    _checkByte(b);
    var product = 0;
    for (var bit = 0; bit < 8; bit++) {
      if ((b & (1 << bit)) != 0) product ^= a << bit;
    }
    for (var degree = 14; degree >= 8; degree--) {
      if ((product & (1 << degree)) != 0) {
        product ^= _modulus << (degree - 8);
      }
    }
    return product;
  }

  int _power(int value, int exponent) {
    var result = 1;
    while (exponent != 0) {
      if (exponent.isOdd) result = multiply(result, value);
      value = multiply(value, value);
      exponent >>= 1;
    }
    return result;
  }

  int exp(int a) {
    RangeError.checkValueInInterval(a, 0, 255, 'exponent');
    return _power(2, a);
  }

  int log(int a) {
    RangeError.checkValueInInterval(a, 1, 255, 'value');
    var candidate = 1;
    for (var exponent = 0; exponent < 255; exponent++) {
      if (candidate == a) return exponent;
      candidate = multiply(candidate, 2);
    }
    throw StateError('The field generator does not span this value.');
  }

  int inverse(int a) {
    RangeError.checkValueInInterval(a, 1, 255, 'value');
    return _power(a, 254);
  }

  static void _checkByte(int value) {
    RangeError.checkValueInInterval(value, 0, 255, 'field element');
  }
}
