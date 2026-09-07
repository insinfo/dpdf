import 'package:test/test.dart';
import 'package:dpdf/src/kernel/geom/matrix.dart';

void main() {
  group('Matrix', () {
    test('TestMultiply', () {
      final m1 = CraftMatrix.fromAffine(2, 3, 4, 5, 6, 7);
      final m2 = CraftMatrix.fromAffine(8, 9, 10, 11, 12, 13);
      final shouldBe = CraftMatrix.fromAffine(46, 51, 82, 91, 130, 144);
      final rslt = m1.multiply(m2);
      expect(rslt, equals(shouldBe));
    });

    test('TestDeterminant', () {
      final m = CraftMatrix.fromAffine(2, 3, 4, 5, 6, 7);
      expect(m.getDeterminant(), closeTo(-2.0, 0.001));
    });

    test('TestSubtract', () {
      final m1 = CraftMatrix.fromAffine(1, 2, 3, 4, 5, 6);
      final m2 = CraftMatrix.fromAffine(6, 5, 4, 3, 2, 1);
      final shouldBe = CraftMatrix.fromValues(-5, -3, 0, -1, 1, 0, 3, 5, 0);
      final rslt = m1.subtract(m2);
      expect(rslt, equals(shouldBe));
    });

    test('TestAdd', () {
      final m1 = CraftMatrix.fromAffine(1, 2, 3, 4, 5, 6);
      final m2 = CraftMatrix.fromAffine(6, 5, 4, 3, 2, 1);
      final shouldBe = CraftMatrix.fromValues(7, 7, 0, 7, 7, 0, 7, 7, 2);
      final rslt = m1.add(m2);
      expect(rslt, equals(shouldBe));
    });
  });
}
