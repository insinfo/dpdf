import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:dpdf/src/kernel/geom/affine_transform.dart';

void main() {
  group('AffineTransform', () {
    test('creates identity transform', () {
      final t = AffineTransform();
      expect(t.isIdentity, isTrue);
      expect(t.scaleX, equals(1.0));
      expect(t.scaleY, equals(1.0));
      expect(t.shearX, equals(0.0));
      expect(t.shearY, equals(0.0));
      expect(t.translateX, equals(0.0));
      expect(t.translateY, equals(0.0));
    });

    test('creates copy', () {
      final t1 = AffineTransform.fromValues(1, 2, 3, 4, 5, 6);
      final t2 = AffineTransform.copy(t1);
      expect(t2.m00, equals(1.0));
      expect(t2.m10, equals(2.0));
      expect(t2.m01, equals(3.0));
      expect(t2.m11, equals(4.0));
      expect(t2.m02, equals(5.0));
      expect(t2.m12, equals(6.0));
    });

    test('translation works', () {
      final t = AffineTransform.getTranslateInstance(10, 20);
      expect(t.translateX, equals(10.0));
      expect(t.translateY, equals(20.0));
      final point = t.transformPoint(0, 0);
      expect(point[0], equals(10.0));
      expect(point[1], equals(20.0));
    });

    test('scaling works', () {
      final t = AffineTransform.getScaleInstance(2, 3);
      expect(t.scaleX, equals(2.0));
      expect(t.scaleY, equals(3.0));
      final point = t.transformPoint(5, 10);
      expect(point[0], equals(10.0));
      expect(point[1], equals(30.0));
    });

    test('rotation works', () {
      final t = AffineTransform.getRotateInstance(math.pi / 2);
      final point = t.transformPoint(1, 0);
      expect(point[0], closeTo(0, 0.0001));
      expect(point[1], closeTo(1, 0.0001));
    });

    test('shear works', () {
      final t = AffineTransform.getShearInstance(1, 0);
      final point = t.transformPoint(1, 1);
      expect(point[0], equals(2.0)); // x + shearX * y
      expect(point[1], equals(1.0));
    });

    test('concatenate combines transforms', () {
      final t1 = AffineTransform.getTranslateInstance(10, 0);
      final t2 = AffineTransform.getScaleInstance(2, 2);
      t1.concatenate(t2);
      final point = t1.transformPoint(5, 5);
      expect(point[0], equals(20.0)); // (5 * 2) + 10
      expect(point[1], equals(10.0));
    });

    test('determinant calculates correctly', () {
      final t = AffineTransform();
      expect(t.determinant, equals(1.0));

      final t2 = AffineTransform.getScaleInstance(2, 3);
      expect(t2.determinant, equals(6.0));
    });

    test('createInverse works', () {
      final t = AffineTransform.getTranslateInstance(10, 20);
      final inv = t.createInverse();
      final point = t.transformPoint(0, 0);
      final back = inv.transformPoint(point[0], point[1]);
      expect(back[0], closeTo(0, 0.0001));
      expect(back[1], closeTo(0, 0.0001));
    });

    test('inverseTransformPoint works', () {
      final t = AffineTransform.getTranslateInstance(10, 20);
      final point = t.inverseTransformPoint(10, 20);
      expect(point[0], closeTo(0, 0.0001));
      expect(point[1], closeTo(0, 0.0001));
    });

    test('transformPoints transforms array', () {
      final t = AffineTransform.getTranslateInstance(10, 20);
      final points = t.transformPoints([0.0, 0.0, 5.0, 5.0]);
      expect(points[0], equals(10.0));
      expect(points[1], equals(20.0));
      expect(points[2], equals(15.0));
      expect(points[3], equals(25.0));
    });

    test('matrix getter returns correct values', () {
      final t = AffineTransform.fromValues(1, 2, 3, 4, 5, 6);
      final m = t.matrix;
      expect(m, equals([1.0, 2.0, 3.0, 4.0, 5.0, 6.0]));
    });

    test('setToIdentity resets transform', () {
      final t = AffineTransform.getTranslateInstance(10, 20);
      t.setToIdentity();
      expect(t.isIdentity, isTrue);
    });

    test('equals compares correctly', () {
      final t1 = AffineTransform.fromValues(1, 2, 3, 4, 5, 6);
      final t2 = AffineTransform.fromValues(1, 2, 3, 4, 5, 6);
      final t3 = AffineTransform.fromValues(1, 2, 3, 4, 5, 7);
      expect(t1 == t2, isTrue);
      expect(t1 == t3, isFalse);
    });
  });
}
