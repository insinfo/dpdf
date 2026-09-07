import 'package:test/test.dart';
import 'package:dpdf/src/kernel/geom/vector.dart';

void main() {
  group('Vector', () {
    test('creates with coordinates', () {
      final v = Vector(1.0, 2.0, 3.0);
      expect(v.x, equals(1.0));
      expect(v.y, equals(2.0));
      expect(v.z, equals(3.0));
    });

    test('get returns correct values', () {
      final v = Vector(1.0, 2.0, 3.0);
      expect(v.get(Vector.i1), equals(1.0));
      expect(v.get(Vector.i2), equals(2.0));
      expect(v.get(Vector.i3), equals(3.0));
    });

    test('subtract works correctly', () {
      final v1 = Vector(5.0, 7.0, 9.0);
      final v2 = Vector(1.0, 2.0, 3.0);
      final result = v1.subtract(v2);
      expect(result.x, equals(4.0));
      expect(result.y, equals(5.0));
      expect(result.z, equals(6.0));
    });

    test('add works correctly', () {
      final v1 = Vector(1.0, 2.0, 3.0);
      final v2 = Vector(4.0, 5.0, 6.0);
      final result = v1.add(v2);
      expect(result.x, equals(5.0));
      expect(result.y, equals(7.0));
      expect(result.z, equals(9.0));
    });

    test('multiply scales vector', () {
      final v = Vector(2.0, 3.0, 4.0);
      final result = v.multiply(2.0);
      expect(result.x, equals(4.0));
      expect(result.y, equals(6.0));
      expect(result.z, equals(8.0));
    });

    test('dot product calculates correctly', () {
      final v1 = Vector(1.0, 2.0, 3.0);
      final v2 = Vector(4.0, 5.0, 6.0);
      expect(v1.dot(v2), equals(32.0)); // 1*4 + 2*5 + 3*6 = 32
    });

    test('length calculates correctly', () {
      final v = Vector(3.0, 4.0, 0.0);
      expect(v.length(), equals(5.0));
    });

    test('lengthSquared calculates correctly', () {
      final v = Vector(3.0, 4.0, 0.0);
      expect(v.lengthSquared(), equals(25.0));
    });

    test('normalize creates unit vector', () {
      final v = Vector(3.0, 4.0, 0.0);
      final normalized = v.normalize();
      expect(normalized.x, closeTo(0.6, 0.001));
      expect(normalized.y, closeTo(0.8, 0.001));
      expect(normalized.length(), closeTo(1.0, 0.001));
    });

    test('equals compares correctly', () {
      final v1 = Vector(1.0, 2.0, 3.0);
      final v2 = Vector(1.0, 2.0, 3.0);
      final v3 = Vector(1.0, 2.0, 4.0);
      expect(v1 == v2, isTrue);
      expect(v1 == v3, isFalse);
    });

    test('toString formats correctly', () {
      final v = Vector(1.0, 2.0, 3.0);
      expect(v.toString(), equals('1.0,2.0,3.0'));
    });
  });
}
