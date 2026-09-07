import 'package:dpdf/src/kernel/geom/matrix.dart';
import 'package:test/test.dart';

void main() {
  test('general matrix composition and immutable arithmetic', () {
    final left = CraftMatrix.fromValues(1, 2, 3, 4, 5, 6, 7, 8, 9);
    final right = CraftMatrix.fromValues(9, 8, 7, 6, 5, 4, 3, 2, 1);
    final result = left.multiply(right);
    expect(
        List.generate(9, result.get), [30, 24, 18, 84, 69, 54, 138, 114, 90]);
    expect(left.get(0), 1);
    expect(left.add(right).subtract(right), left);
    expect(left.getDeterminant(), 0);
    expect(CraftMatrix.fromAffine(2, 0, 0, 3, 5, 7).getDeterminant(), 6);
  });
}
