import 'dart:typed_data';
import 'package:dpdf/src/commons/utils/value_collections.dart';

/// Row-major 3×3 values stored at single precision.
/// PDF affine values occupy rows [a,b,0], [c,d,0], [e,f,1].
class Matrix {
  static const int I11 = 0, I12 = 1, I13 = 2;
  static const int I21 = 3, I22 = 4, I23 = 5;
  static const int I31 = 6, I32 = 7, I33 = 8;
  final Float32List _vals;
  Matrix._values(Iterable<double> values)
      : _vals = Float32List.fromList(values.toList());
  Matrix() : this._values([1, 0, 0, 0, 1, 0, 0, 0, 1]);
  Matrix.translation(double tx, double ty)
      : this._values([1, 0, 0, 0, 1, 0, tx, ty, 1]);
  Matrix.fromValues(double e11, double e12, double e13, double e21, double e22,
      double e23, double e31, double e32, double e33)
      : this._values([e11, e12, e13, e21, e22, e23, e31, e32, e33]);
  Matrix.fromAffine(double a, double b, double c, double d, double e, double f)
      : this._values([a, b, 0, c, d, 0, e, f, 1]);
  double get(int index) => _vals[index];

  Matrix multiply(Matrix by) => Matrix._values(Iterable.generate(9, (cell) {
        final row = cell ~/ 3, column = cell % 3;
        var value = _vals[row * 3] * by._vals[column];
        for (var term = 1; term < 3; term++) {
          value += _vals[row * 3 + term] * by._vals[term * 3 + column];
        }
        return value;
      }));
  Matrix add(Matrix arg) => Matrix._values(
      Iterable.generate(9, (cell) => _vals[cell] + arg._vals[cell]));
  Matrix subtract(Matrix arg) => Matrix._values(
      Iterable.generate(9, (cell) => _vals[cell] - arg._vals[cell]));
  double getDeterminant() {
    var determinant = 0.0;
    for (var column = 0; column < 3; column++) {
      final next = (column + 1) % 3, last = (column + 2) % 3;
      determinant += _vals[column] *
          (_vals[3 + next] * _vals[6 + last] -
              _vals[3 + last] * _vals[6 + next]);
    }
    return determinant;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Matrix && ValueCollections.listsEqual(_vals, other._vals);
  @override
  int get hashCode => ValueCollections.listHash(_vals);
  @override
  String toString() =>
      Iterable.generate(3, (row) => _vals.skip(row * 3).take(3).join('\t'))
          .join('\n');
}
