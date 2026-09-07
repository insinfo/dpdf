import 'gf_256.dart';

/// A byte polynomial with coefficients stored from constant to leading term.
class GF256Poly {
  final GF256 _field;
  final List<int> _terms;

  GF256Poly(GF256 field, List<int> coefficients)
      : this._ascending(field, coefficients.reversed.toList());

  GF256Poly._ascending(this._field, List<int> terms)
      : _terms = _normalize(terms);

  static List<int> _normalize(List<int> terms) {
    if (terms.isEmpty) throw ArgumentError('A polynomial needs a coefficient.');
    for (final value in terms) {
      RangeError.checkValueInInterval(value, 0, 255, 'coefficient');
    }
    var length = terms.length;
    while (length > 1 && terms[length - 1] == 0) {
      length--;
    }
    return List<int>.unmodifiable(terms.take(length));
  }

  List<int> getCoefficients() => _terms.reversed.toList();
  int getDegree() => _terms.length - 1;
  bool isZero() => _terms.length == 1 && _terms[0] == 0;
  int getCoefficient(int degree) => _terms[degree];

  int evaluateAt(int value) => _terms.reversed
      .fold(0, (sum, coefficient) => _field.multiply(sum, value) ^ coefficient);

  void _sameField(GF256Poly other) {
    if (!identical(_field, other._field)) {
      throw ArgumentError('Polynomial operands must belong to the same field.');
    }
  }

  GF256Poly addOrSubtract(GF256Poly other) {
    _sameField(other);
    final length = _terms.length > other._terms.length
        ? _terms.length
        : other._terms.length;
    return GF256Poly._ascending(
        _field,
        List.generate(
            length,
            (degree) =>
                (degree < _terms.length ? _terms[degree] : 0) ^
                (degree < other._terms.length ? other._terms[degree] : 0)));
  }

  GF256Poly multiply(dynamic other) {
    if (other is int) {
      return GF256Poly._ascending(_field,
          _terms.map((value) => _field.multiply(value, other)).toList());
    }
    if (other is! GF256Poly) {
      throw ArgumentError('Multiply by a field element or another polynomial.');
    }
    _sameField(other);
    final terms = List<int>.filled(getDegree() + other.getDegree() + 1, 0);
    for (var left = 0; left < _terms.length; left++) {
      for (var right = 0; right < other._terms.length; right++) {
        terms[left + right] ^=
            _field.multiply(_terms[left], other._terms[right]);
      }
    }
    return GF256Poly._ascending(_field, terms);
  }

  GF256Poly multiplyByMonomial(int degree, int coefficient) {
    RangeError.checkNotNegative(degree, 'degree');
    return GF256Poly._ascending(_field, [
      ...List<int>.filled(degree, 0),
      ..._terms.map((value) => _field.multiply(value, coefficient)),
    ]);
  }

  List<GF256Poly> divide(GF256Poly other) {
    _sameField(other);
    if (other.isZero()) throw ArgumentError('The divisor polynomial is zero.');
    if (getDegree() < other.getDegree()) return [_field.getZero(), this];
    final remainder = List<int>.of(_terms);
    final quotient = List<int>.filled(getDegree() - other.getDegree() + 1, 0);
    final reciprocal = _field.inverse(other._terms.last);
    for (var shift = quotient.length - 1; shift >= 0; shift--) {
      final factor =
          _field.multiply(remainder[shift + other.getDegree()], reciprocal);
      quotient[shift] = factor;
      for (var degree = 0; degree < other._terms.length; degree++) {
        remainder[shift + degree] ^=
            _field.multiply(factor, other._terms[degree]);
      }
    }
    return [
      GF256Poly._ascending(_field, quotient),
      GF256Poly._ascending(_field, remainder),
    ];
  }

  @override
  String toString() {
    final parts = <String>[];
    for (var degree = getDegree(); degree >= 0; degree--) {
      final coefficient = _terms[degree];
      if (coefficient == 0) continue;
      final exponent = _field.log(coefficient);
      final scalar = exponent == 0
          ? '1'
          : exponent == 1
              ? 'a'
              : 'a^$exponent';
      final variable = degree == 0
          ? ''
          : degree == 1
              ? 'x'
              : 'x^$degree';
      parts.add('${coefficient == 1 && degree != 0 ? '' : scalar}$variable');
    }
    return parts.join(' + ');
  }
}
