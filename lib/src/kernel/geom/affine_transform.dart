import 'dart:math' as math;

/// Represents an affine transformation, which is a combination of linear
/// transformations such as translation, scaling, rotation, and shearing.
///
/// This is a special case of a 3x3 Matrix.
class AffineTransform {
  // Transform type constants
  static const int typeIdentity = 0;
  static const int typeTranslation = 1;
  static const int typeUniformScale = 2;
  static const int typeGeneralScale = 4;
  static const int typeQuadrantRotation = 8;
  static const int typeGeneralRotation = 16;
  static const int typeGeneralTransform = 32;
  static const int typeFlip = 64;
  static const int typeMaskScale = typeUniformScale | typeGeneralScale;
  static const int typeMaskRotation =
      typeQuadrantRotation | typeGeneralRotation;
  static const int _typeUnknown = -1;
  static const double _zero = 1E-10;

  /// Matrix values: [m00, m10, m01, m11, m02, m12]
  double m00 = 1.0;
  double m10 = 0.0;
  double m01 = 0.0;
  double m11 = 1.0;
  double m02 = 0.0;
  double m12 = 0.0;
  int _type = typeIdentity;

  /// Creates an identity AffineTransform.
  AffineTransform() {
    _type = typeIdentity;
    m00 = m11 = 1.0;
    m10 = m01 = m02 = m12 = 0.0;
  }

  /// Creates a copy of another AffineTransform.
  AffineTransform.copy(AffineTransform t)
      : _type = t._type,
        m00 = t.m00,
        m10 = t.m10,
        m01 = t.m01,
        m11 = t.m11,
        m02 = t.m02,
        m12 = t.m12;

  /// Creates an AffineTransform with the specified values.
  AffineTransform.fromValues(
      this.m00, this.m10, this.m01, this.m11, this.m02, this.m12)
      : _type = _typeUnknown;

  /// Creates an AffineTransform from a list of values.
  AffineTransform.fromList(List<double> matrix) : _type = _typeUnknown {
    m00 = matrix[0];
    m10 = matrix[1];
    m01 = matrix[2];
    m11 = matrix[3];
    if (matrix.length > 4) {
      m02 = matrix[4];
      m12 = matrix[5];
    }
  }

  /// Returns the matrix as a list [m00, m10, m01, m11, m02, m12].
  List<double> get matrix => [m00, m10, m01, m11, m02, m12];

  /// Gets the transformation type.
  int getTransformType() {
    if (_type != _typeUnknown) return _type;

    int type = 0;
    if (m00 * m01 + m10 * m11 != 0.0) {
      type |= typeGeneralTransform;
      return type;
    }
    if (m02 != 0.0 || m12 != 0.0) {
      type |= typeTranslation;
    } else if (m00 == 1.0 && m11 == 1.0 && m01 == 0.0 && m10 == 0.0) {
      return typeIdentity;
    }
    if (m00 * m11 - m01 * m10 < 0.0) {
      type |= typeFlip;
    }
    double dx = m00 * m00 + m10 * m10;
    double dy = m01 * m01 + m11 * m11;
    if (dx != dy) {
      type |= typeGeneralScale;
    } else if (dx != 1.0) {
      type |= typeUniformScale;
    }
    if ((m00 == 0.0 && m11 == 0.0) ||
        (m10 == 0.0 && m01 == 0.0 && (m00 < 0.0 || m11 < 0.0))) {
      type |= typeQuadrantRotation;
    } else if (m01 != 0.0 || m10 != 0.0) {
      type |= typeGeneralRotation;
    }
    return type;
  }

  /// Gets the scale factor of the x-axis.
  double get scaleX => m00;

  /// Gets the scale factor of the y-axis.
  double get scaleY => m11;

  /// Gets the shear factor of the x-axis.
  double get shearX => m01;

  /// Gets the shear factor of the y-axis.
  double get shearY => m10;

  /// Gets the translation factor of the x-axis.
  double get translateX => m02;

  /// Gets the translation factor of the y-axis.
  double get translateY => m12;

  /// Returns true if this is an identity transformation.
  bool get isIdentity => getTransformType() == typeIdentity;

  /// Gets the determinant of the matrix.
  double get determinant => m00 * m11 - m01 * m10;

  /// Sets the transform values.
  void setTransform(
      double m00, double m10, double m01, double m11, double m02, double m12) {
    _type = _typeUnknown;
    this.m00 = m00;
    this.m10 = m10;
    this.m01 = m01;
    this.m11 = m11;
    this.m02 = m02;
    this.m12 = m12;
  }

  /// Copies values from another transform.
  void setTransformFrom(AffineTransform t) {
    _type = t._type;
    setTransform(t.m00, t.m10, t.m01, t.m11, t.m02, t.m12);
  }

  /// Resets to identity.
  void setToIdentity() {
    _type = typeIdentity;
    m00 = m11 = 1.0;
    m10 = m01 = m02 = m12 = 0.0;
  }

  /// Sets to a translation.
  void setToTranslation(double mx, double my) {
    m00 = m11 = 1.0;
    m01 = m10 = 0.0;
    m02 = mx;
    m12 = my;
    _type = (mx == 0 && my == 0) ? typeIdentity : typeTranslation;
  }

  /// Sets to a scale transformation.
  void setToScale(double scx, double scy) {
    m00 = scx;
    m11 = scy;
    m10 = m01 = m02 = m12 = 0.0;
    _type = (scx != 1.0 || scy != 1.0) ? _typeUnknown : typeIdentity;
  }

  /// Sets to a shear transformation.
  void setToShear(double shx, double shy) {
    m00 = m11 = 1.0;
    m02 = m12 = 0.0;
    m01 = shx;
    m10 = shy;
    _type = (shx != 0.0 || shy != 0.0) ? _typeUnknown : typeIdentity;
  }

  /// Sets to a rotation.
  void setToRotation(double angle) {
    double sin = math.sin(angle);
    double cos = math.cos(angle);
    if (cos.abs() < _zero) {
      cos = 0.0;
      sin = sin > 0.0 ? 1.0 : -1.0;
    } else if (sin.abs() < _zero) {
      sin = 0.0;
      cos = cos > 0.0 ? 1.0 : -1.0;
    }
    m00 = m11 = cos;
    m01 = -sin;
    m10 = sin;
    m02 = m12 = 0.0;
    _type = _typeUnknown;
  }

  /// Sets to a rotation around a point.
  void setToRotationAround(double angle, double px, double py) {
    setToRotation(angle);
    m02 = px * (1 - m00) + py * m10;
    m12 = py * (1 - m00) - px * m10;
    _type = _typeUnknown;
  }

  /// Creates a translation transform.
  static AffineTransform getTranslateInstance(double mx, double my) {
    final t = AffineTransform();
    t.setToTranslation(mx, my);
    return t;
  }

  /// Creates a scale transform.
  static AffineTransform getScaleInstance(double scx, double scy) {
    final t = AffineTransform();
    t.setToScale(scx, scy);
    return t;
  }

  /// Creates a shear transform.
  static AffineTransform getShearInstance(double shx, double shy) {
    final t = AffineTransform();
    t.setToShear(shx, shy);
    return t;
  }

  /// Creates a rotation transform.
  static AffineTransform getRotateInstance(double angle) {
    final t = AffineTransform();
    t.setToRotation(angle);
    return t;
  }

  /// Creates a rotation transform around a point.
  static AffineTransform getRotateInstanceAround(
      double angle, double x, double y) {
    final t = AffineTransform();
    t.setToRotationAround(angle, x, y);
    return t;
  }

  /// Applies translation.
  void translate(double mx, double my) {
    concatenate(AffineTransform.getTranslateInstance(mx, my));
  }

  /// Applies scaling.
  void scale(double scx, double scy) {
    concatenate(AffineTransform.getScaleInstance(scx, scy));
  }

  /// Applies shearing.
  void shear(double shx, double shy) {
    concatenate(AffineTransform.getShearInstance(shx, shy));
  }

  /// Applies rotation.
  void rotate(double angle) {
    concatenate(AffineTransform.getRotateInstance(angle));
  }

  /// Applies rotation around a point.
  void rotateAround(double angle, double px, double py) {
    concatenate(AffineTransform.getRotateInstanceAround(angle, px, py));
  }

  /// Multiplies two transforms.
  AffineTransform _multiply(AffineTransform t1, AffineTransform t2) {
    return AffineTransform.fromValues(
      t1.m00 * t2.m00 + t1.m10 * t2.m01,
      t1.m00 * t2.m10 + t1.m10 * t2.m11,
      t1.m01 * t2.m00 + t1.m11 * t2.m01,
      t1.m01 * t2.m10 + t1.m11 * t2.m11,
      t1.m02 * t2.m00 + t1.m12 * t2.m01 + t2.m02,
      t1.m02 * t2.m10 + t1.m12 * t2.m11 + t2.m12,
    );
  }

  /// Concatenates transform (this = t * this).
  void concatenate(AffineTransform t) {
    setTransformFrom(_multiply(t, this));
  }

  /// Pre-concatenates transform (this = this * t).
  void preConcatenate(AffineTransform t) {
    setTransformFrom(_multiply(this, t));
  }

  /// Creates the inverse transform.
  AffineTransform createInverse() {
    double det = determinant;
    if (det.abs() < _zero) {
      throw StateError('Determinant is zero, cannot invert transformation');
    }
    return AffineTransform.fromValues(
      m11 / det,
      -m10 / det,
      -m01 / det,
      m00 / det,
      (m01 * m12 - m11 * m02) / det,
      (m10 * m02 - m00 * m12) / det,
    );
  }

  /// Transforms a point (x, y) and returns [newX, newY].
  List<double> transformPoint(double x, double y) {
    return [
      x * m00 + y * m01 + m02,
      x * m10 + y * m11 + m12,
    ];
  }

  /// Transforms an array of coordinates [x1, y1, x2, y2, ...].
  List<double> transformPoints(List<double> src) {
    final dst = List<double>.filled(src.length, 0);
    for (int i = 0; i < src.length; i += 2) {
      double x = src[i];
      double y = src[i + 1];
      dst[i] = x * m00 + y * m01 + m02;
      dst[i + 1] = x * m10 + y * m11 + m12;
    }
    return dst;
  }

  /// Inverse transforms a point.
  List<double> inverseTransformPoint(double x, double y) {
    double det = determinant;
    if (det.abs() < _zero) {
      throw StateError('Determinant is zero, cannot inverse transform');
    }
    x -= m02;
    y -= m12;
    return [
      (x * m11 - y * m01) / det,
      (y * m00 - x * m10) / det,
    ];
  }

  @override
  String toString() {
    return 'AffineTransform[[$m00, $m01, $m02], [$m10, $m11, $m12]]';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AffineTransform) return false;
    return m00 == other.m00 &&
        m10 == other.m10 &&
        m01 == other.m01 &&
        m11 == other.m11 &&
        m02 == other.m02 &&
        m12 == other.m12;
  }

  @override
  int get hashCode {
    return Object.hash(m00, m10, m01, m11, m02, m12);
  }
}
