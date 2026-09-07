import 'package:dpdf/src/kernel/geom/affine_transform.dart';
import 'package:test/test.dart';

void expectPoint(List<double> actual, List<double> expected) {
  for (var axis = 0; axis < 2; axis++) {
    expect(actual[axis], closeTo(expected[axis], 1e-10));
  }
}

void main() {
  test('Both composition orders agree with sequential point transformations',
      () {
    final first = AffineTransform.fromValues(2, -3, 5, 7, 11, -13);
    final second = AffineTransform.fromValues(-17, 19, 23, 29, -31, 37);
    final before = AffineTransform.copy(first)..concatenate(second);
    final after = AffineTransform.copy(first)..preConcatenate(second);
    for (final point in [
      [0.0, 0.0],
      [1.0, 0.0],
      [0.0, 1.0],
      [2.25, -7.5]
    ]) {
      final secondPoint = second.transformPoint(point[0], point[1]);
      final firstPoint = first.transformPoint(point[0], point[1]);
      expectPoint(before.transformPoint(point[0], point[1]),
          first.transformPoint(secondPoint[0], secondPoint[1]));
      expectPoint(after.transformPoint(point[0], point[1]),
          second.transformPoint(firstPoint[0], firstPoint[1]));
    }
    expect(before.matrix, isNot(after.matrix));
  });
  test('Composition retains precision beyond Float32 with large translations',
      () {
    final transform = AffineTransform.fromValues(
        1 + 1e-12, 2e-13, -3e-13, 1 - 2e-12, 1e12 + 0.125, -1e12 - 0.25);
    final expected = transform.matrix;
    transform.concatenate(AffineTransform());
    expect(transform.matrix, expected);
    transform.preConcatenate(AffineTransform());
    expect(transform.matrix, expected);
  });
  test('Self composition uses a stable operand snapshot', () {
    final transform = AffineTransform.fromValues(1.5, 0.5, -0.25, 2, 7, -11);
    final first = transform.transformPoint(3, 9);
    final expected = transform.transformPoint(first[0], first[1]);
    transform.concatenate(transform);
    expectPoint(transform.transformPoint(3, 9), expected);
  });
  test('Composition with inverse returns the original coordinates', () {
    final original = AffineTransform.fromValues(1.25, 0.5, -0.75, 2.5, 4, -6);
    final inverse = original.createInverse();
    final before = AffineTransform.copy(original)..concatenate(inverse);
    final after = AffineTransform.copy(original)..preConcatenate(inverse);
    expectPoint(before.transformPoint(123, -456), [123, -456]);
    expectPoint(after.transformPoint(123, -456), [123, -456]);
  });
}
