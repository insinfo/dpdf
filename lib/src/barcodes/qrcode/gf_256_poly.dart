import 'gf_256.dart';

/// Represents a polynomial whose coefficients are elements of GF(256).
class GF256Poly {
  final GF256 _field;
  late List<int> _coefficients;

  /// [field] - the GF256 instance representing the field to use
  /// [coefficients] - coefficients as ints representing elements of GF(256)
  GF256Poly(this._field, List<int> coefficients) {
    if (coefficients.isEmpty) {
      throw ArgumentError();
    }
    int coefficientsLength = coefficients.length;
    if (coefficientsLength > 1 && coefficients[0] == 0) {
      // Leading term must be non-zero for anything except the constant polynomial "0"
      int firstNonZero = 1;
      while (firstNonZero < coefficientsLength &&
          coefficients[firstNonZero] == 0) {
        firstNonZero++;
      }
      if (firstNonZero == coefficientsLength) {
        _coefficients = _field.getZero().getCoefficients();
      } else {
        _coefficients = List<int>.filled(coefficientsLength - firstNonZero, 0);
        List.copyRange(_coefficients, 0, coefficients, firstNonZero);
      }
    } else {
      _coefficients = coefficients;
    }
  }

  List<int> getCoefficients() {
    return _coefficients;
  }

  /// Returns degree of this polynomial
  int getDegree() {
    return _coefficients.length - 1;
  }

  /// Returns true iff this polynomial is the monomial "0"
  bool isZero() {
    return _coefficients[0] == 0;
  }

  /// Returns coefficient of x^degree term in this polynomial
  int getCoefficient(int degree) {
    return _coefficients[_coefficients.length - 1 - degree];
  }

  /// Returns evaluation of this polynomial at a given point
  int evaluateAt(int a) {
    if (a == 0) {
      // Just return the x^0 coefficient
      return getCoefficient(0);
    }
    int size = _coefficients.length;
    if (a == 1) {
      // Just the sum of the coefficients
      int result = 0;
      for (int i = 0; i < size; i++) {
        result = GF256.addOrSubtract(result, _coefficients[i]);
      }
      return result;
    }
    int result = _coefficients[0];
    for (int i = 1; i < size; i++) {
      result =
          GF256.addOrSubtract(_field.multiply(a, result), _coefficients[i]);
    }
    return result;
  }

  /// GF addition or subtraction (they are identical for a GF(2^n)
  GF256Poly addOrSubtract(GF256Poly other) {
    if (_field != other._field) {
      throw ArgumentError("GF256Polys do not have same GF256 field");
    }
    if (isZero()) {
      return other;
    }
    if (other.isZero()) {
      return this;
    }
    List<int> smallerCoefficients = _coefficients;
    List<int> largerCoefficients = other._coefficients;
    if (smallerCoefficients.length > largerCoefficients.length) {
      List<int> temp = smallerCoefficients;
      smallerCoefficients = largerCoefficients;
      largerCoefficients = temp;
    }
    List<int> sumDiff = List<int>.filled(largerCoefficients.length, 0);
    int lengthDiff = largerCoefficients.length - smallerCoefficients.length;
    // Copy high-order terms only found in higher-degree polynomial's coefficients
    List.copyRange(sumDiff, 0, largerCoefficients, 0, lengthDiff);
    for (int i = lengthDiff; i < largerCoefficients.length; i++) {
      sumDiff[i] = GF256.addOrSubtract(
          smallerCoefficients[i - lengthDiff], largerCoefficients[i]);
    }
    return GF256Poly(_field, sumDiff);
  }

  /// GF multiplication
  GF256Poly multiply(dynamic other) {
    if (other is GF256Poly) {
      return _multiplyPoly(other);
    } else if (other is int) {
      return _multiplyScalar(other);
    }
    throw ArgumentError("Unsupported type for multiply");
  }

  GF256Poly _multiplyPoly(GF256Poly other) {
    if (_field != other._field) {
      throw ArgumentError("GF256Polys do not have same GF256 field");
    }
    if (isZero() || other.isZero()) {
      return _field.getZero();
    }
    List<int> aCoefficients = _coefficients;
    int aLength = aCoefficients.length;
    List<int> bCoefficients = other._coefficients;
    int bLength = bCoefficients.length;
    List<int> product = List<int>.filled(aLength + bLength - 1, 0);
    for (int i = 0; i < aLength; i++) {
      int aCoeff = aCoefficients[i];
      for (int j = 0; j < bLength; j++) {
        product[i + j] = GF256.addOrSubtract(
            product[i + j], _field.multiply(aCoeff, bCoefficients[j]));
      }
    }
    return GF256Poly(_field, product);
  }

  GF256Poly _multiplyScalar(int scalar) {
    if (scalar == 0) {
      return _field.getZero();
    }
    if (scalar == 1) {
      return this;
    }
    int size = _coefficients.length;
    List<int> product = List<int>.filled(size, 0);
    for (int i = 0; i < size; i++) {
      product[i] = _field.multiply(_coefficients[i], scalar);
    }
    return GF256Poly(_field, product);
  }

  GF256Poly multiplyByMonomial(int degree, int coefficient) {
    if (degree < 0) {
      throw ArgumentError();
    }
    if (coefficient == 0) {
      return _field.getZero();
    }
    int size = _coefficients.length;
    List<int> product = List<int>.filled(size + degree, 0);
    for (int i = 0; i < size; i++) {
      product[i] = _field.multiply(_coefficients[i], coefficient);
    }
    return GF256Poly(_field, product);
  }

  List<GF256Poly> divide(GF256Poly other) {
    if (_field != other._field) {
      throw ArgumentError("GF256Polys do not have same GF256 field");
    }
    if (other.isZero()) {
      throw ArgumentError("Divide by 0");
    }
    GF256Poly quotient = _field.getZero();
    GF256Poly remainder = this;
    int denominatorLeadingTerm = other.getCoefficient(other.getDegree());
    int inverseDenominatorLeadingTerm = _field.inverse(denominatorLeadingTerm);
    while (remainder.getDegree() >= other.getDegree() && !remainder.isZero()) {
      int degreeDifference = remainder.getDegree() - other.getDegree();
      int scale = _field.multiply(
          remainder.getCoefficient(remainder.getDegree()),
          inverseDenominatorLeadingTerm);
      GF256Poly term = other.multiplyByMonomial(degreeDifference, scale);
      GF256Poly iterationQuotient =
          _field.buildMonomial(degreeDifference, scale);
      quotient = quotient.addOrSubtract(iterationQuotient);
      remainder = remainder.addOrSubtract(term);
    }
    return [quotient, remainder];
  }

  @override
  String toString() {
    StringBuffer result = StringBuffer();
    for (int degree = getDegree(); degree >= 0; degree--) {
      int coefficient = getCoefficient(degree);
      if (coefficient != 0) {
        if (coefficient < 0) {
          result.write(" - ");
          coefficient = -coefficient;
        } else {
          if (result.length > 0) {
            result.write(" + ");
          }
        }
        if (degree == 0 || coefficient != 1) {
          int alphaPower = _field.log(coefficient);
          if (alphaPower == 0) {
            result.write('1');
          } else {
            if (alphaPower == 1) {
              result.write('a');
            } else {
              result.write("a^");
              result.write(alphaPower);
            }
          }
        }
        if (degree != 0) {
          if (degree == 1) {
            result.write('x');
          } else {
            result.write("x^");
            result.write(degree);
          }
        }
      }
    }
    return result.toString();
  }
}
