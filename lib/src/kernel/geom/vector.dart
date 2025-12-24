import 'dart:math' as math;

/// Represents a vector (i.e. a point in space).
///
/// For many PDF related operations, the z coordinate is specified as 1.
/// This is to support the coordinate transformation calculations.
class Vector {
  /// Index of the X coordinate.
  static const int i1 = 0;

  /// Index of the Y coordinate.
  static const int i2 = 1;

  /// Index of the Z coordinate.
  static const int i3 = 2;

  /// The values inside the vector.
  final List<double> _vals;

  /// Creates a new Vector.
  Vector(double x, double y, double z) : _vals = [x, y, z];

  /// Gets the value from a coordinate of the vector.
  double get(int index) => _vals[index];

  /// Gets the X coordinate.
  double get x => _vals[i1];

  /// Gets the Y coordinate.
  double get y => _vals[i2];

  /// Gets the Z coordinate.
  double get z => _vals[i3];

  /// Computes the cross product of this vector and a 3x3 matrix.
  /// Matrix is represented as a list of 9 values in row-major order.
  Vector crossMatrix(List<double> matrix) {
    double newX =
        _vals[i1] * matrix[0] + _vals[i2] * matrix[3] + _vals[i3] * matrix[6];
    double newY =
        _vals[i1] * matrix[1] + _vals[i2] * matrix[4] + _vals[i3] * matrix[7];
    double newZ =
        _vals[i1] * matrix[2] + _vals[i2] * matrix[5] + _vals[i3] * matrix[8];
    return Vector(newX, newY, newZ);
  }

  /// Computes the difference between this vector and the specified vector.
  Vector subtract(Vector v) {
    return Vector(
      _vals[i1] - v._vals[i1],
      _vals[i2] - v._vals[i2],
      _vals[i3] - v._vals[i3],
    );
  }

  /// Computes the sum of this vector and the specified vector.
  Vector add(Vector v) {
    return Vector(
      _vals[i1] + v._vals[i1],
      _vals[i2] + v._vals[i2],
      _vals[i3] + v._vals[i3],
    );
  }

  /// Computes the cross product of this vector and the specified vector.
  Vector cross(Vector other) {
    double newX = _vals[i2] * other._vals[i3] - _vals[i3] * other._vals[i2];
    double newY = _vals[i3] * other._vals[i1] - _vals[i1] * other._vals[i3];
    double newZ = _vals[i1] * other._vals[i2] - _vals[i2] * other._vals[i1];
    return Vector(newX, newY, newZ);
  }

  /// Normalizes the vector (returns the unit vector).
  Vector normalize() {
    double l = length();
    if (l == 0) return Vector(0, 0, 0);
    return Vector(_vals[i1] / l, _vals[i2] / l, _vals[i3] / l);
  }

  /// Multiplies the vector by a scalar.
  Vector multiply(double by) {
    return Vector(_vals[i1] * by, _vals[i2] * by, _vals[i3] * by);
  }

  /// Computes the dot product of this vector with the specified vector.
  double dot(Vector other) {
    return _vals[i1] * other._vals[i1] +
        _vals[i2] * other._vals[i2] +
        _vals[i3] * other._vals[i3];
  }

  /// Computes the length of this vector.
  double length() => math.sqrt(lengthSquared());

  /// Computes the length squared of this vector.
  double lengthSquared() {
    return _vals[i1] * _vals[i1] +
        _vals[i2] * _vals[i2] +
        _vals[i3] * _vals[i3];
  }

  @override
  String toString() => '${_vals[i1]},${_vals[i2]},${_vals[i3]}';

  @override
  int get hashCode {
    int result = 1;
    for (final val in _vals) {
      result = 31 * result + val.hashCode;
    }
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Vector) return false;
    return _vals[i1] == other._vals[i1] &&
        _vals[i2] == other._vals[i2] &&
        _vals[i3] == other._vals[i3];
  }
}
