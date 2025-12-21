import 'dart:typed_data';
import 'package:collection/collection.dart';

/// Keeps all the values of a 3 by 3 matrix and allows you to do some math with matrices.
///
/// Transformation matrix in PDF is a special case of a 3 by 3 matrix
/// [a b 0]
/// [c d 0]
/// [e f 1]
///
/// In its most general form, this matrix is specified by six numbers, usually in the form of an array containing six
/// elements [a b c d e f]. It can represent any linear transformation from one coordinate system to
/// another.
class Matrix {
  /// The row=1, col=1 position ('a') in the matrix.
  static const int I11 = 0;

  /// The row=1, col=2 position ('b') in the matrix.
  static const int I12 = 1;

  /// The row=1, col=3 position (always 0 for 2D) in the matrix.
  static const int I13 = 2;

  /// The row=2, col=1 position ('c') in the matrix.
  static const int I21 = 3;

  /// The row=2, col=2 position ('d') in the matrix.
  static const int I22 = 4;

  /// The row=2, col=3 position (always 0 for 2D) in the matrix.
  static const int I23 = 5;

  /// The row=3, col=1 ('e', or X translation) position in the matrix.
  static const int I31 = 6;

  /// The row=3, col=2 ('f', or Y translation) position in the matrix.
  static const int I32 = 7;

  /// The row=3, col=3 position (always 1 for 2D) in the matrix.
  static const int I33 = 8;

  /// The values inside the matrix (the identity matrix by default).
  final Float32List _vals;

  /// Constructs a new Matrix with identity.
  Matrix() : _vals = Float32List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]);

  /// Constructs a matrix that represents translation.
  /// [tx] x-axis translation
  /// [ty] y-axis translation
  Matrix.translation(double tx, double ty)
      : _vals = Float32List.fromList([1, 0, 0, 0, 1, 0, tx, ty, 1]);

  /// Creates a Matrix with 9 specified entries.
  Matrix.fromValues(double e11, double e12, double e13, double e21, double e22,
      double e23, double e31, double e32, double e33)
      : _vals =
            Float32List.fromList([e11, e12, e13, e21, e22, e23, e31, e32, e33]);

  /// Creates a Matrix with 6 specified entries.
  /// The third column will always be [0 0 1]
  /// (row, column)
  /// [a] element at (1,1)
  /// [b] element at (1,2)
  /// [c] element at (2,1)
  /// [d] element at (2,2)
  /// [e] element at (3,1)
  /// [f] element at (3,2)
  Matrix.fromAffine(double a, double b, double c, double d, double e, double f)
      : _vals = Float32List.fromList([a, b, 0, c, d, 0, e, f, 1]);

  /// Gets a specific value inside the matrix.
  /// [index] an array index corresponding with a value inside the matrix
  /// Returns the value at that specific position.
  double get(int index) {
    return _vals[index];
  }

  /// Multiplies this matrix by 'b' and returns the result.
  /// [by] The matrix to multiply by
  /// Returns the resulting matrix
  Matrix multiply(Matrix by) {
    Matrix rslt = Matrix();
    Float32List a = _vals;
    Float32List b = by._vals;
    Float32List c = rslt._vals;

    c[I11] = a[I11] * b[I11] + a[I12] * b[I21] + a[I13] * b[I31];
    c[I12] = a[I11] * b[I12] + a[I12] * b[I22] + a[I13] * b[I32];
    c[I13] = a[I11] * b[I13] + a[I12] * b[I23] + a[I13] * b[I33];

    c[I21] = a[I21] * b[I11] + a[I22] * b[I21] + a[I23] * b[I31];
    c[I22] = a[I21] * b[I12] + a[I22] * b[I22] + a[I23] * b[I32];
    c[I23] = a[I21] * b[I13] + a[I22] * b[I23] + a[I23] * b[I33];

    c[I31] = a[I31] * b[I11] + a[I32] * b[I21] + a[I33] * b[I31];
    c[I32] = a[I31] * b[I12] + a[I32] * b[I22] + a[I33] * b[I32];
    c[I33] = a[I31] * b[I13] + a[I32] * b[I23] + a[I33] * b[I33];

    return rslt;
  }

  /// Adds a matrix from this matrix and returns the results.
  /// [arg] the matrix to add to this matrix
  /// Returns a Matrix object
  Matrix add(Matrix arg) {
    Matrix rslt = Matrix();
    Float32List a = _vals;
    Float32List b = arg._vals;
    Float32List c = rslt._vals;

    for (int i = 0; i < 9; i++) {
      c[i] = a[i] + b[i];
    }
    return rslt;
  }

  /// Subtracts a matrix from this matrix and returns the results.
  /// [arg] the matrix to subtract from this matrix
  /// Returns a Matrix object
  Matrix subtract(Matrix arg) {
    Matrix rslt = Matrix();
    Float32List a = _vals;
    Float32List b = arg._vals;
    Float32List c = rslt._vals;

    for (int i = 0; i < 9; i++) {
      c[i] = a[i] - b[i];
    }
    return rslt;
  }

  /// Computes the determinant of the matrix.
  /// Returns the determinant of the matrix
  double getDeterminant() {
    return _vals[I11] * _vals[I22] * _vals[I33] +
        _vals[I12] * _vals[I23] * _vals[I31] +
        _vals[I13] * _vals[I21] * _vals[I32] -
        _vals[I11] * _vals[I23] * _vals[I32] -
        _vals[I12] * _vals[I21] * _vals[I33] -
        _vals[I13] * _vals[I22] * _vals[I31];
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Matrix) return false;
    return const ListEquality().equals(_vals, other._vals);
  }

  @override
  int get hashCode => const ListEquality().hash(_vals);

  @override
  String toString() {
    return "${_vals[I11]}\t${_vals[I12]}\t${_vals[I13]}\n"
        "${_vals[I21]}\t${_vals[I22]}\t${_vals[I23]}\n"
        "${_vals[I31]}\t${_vals[I32]}\t${_vals[I33]}";
  }
}
