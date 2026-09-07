import 'package:dpdf/src/barcodes/qrcode/byte_matrix.dart';
import 'package:dpdf/src/barcodes/qrcode/mask_util.dart';
import 'package:test/test.dart';

ByteMatrix grid(List<String> rows) {
  final result = ByteMatrix(rows.first.length, rows.length);
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      result.set(x, y, int.parse(rows[y][x]));
    }
  }
  return result;
}

void main() {
  test('run penalties include each complete horizontal and vertical run', () {
    expect(MaskUtil.repeatedRunPenalty(grid(['1111'])), 0);
    expect(MaskUtil.repeatedRunPenalty(grid(['11111000000'])), 7);
    expect(MaskUtil.repeatedRunPenalty(grid(List.filled(6, '1'))), 4);
    expect(MaskUtil.repeatedRunPenalty(grid(['11111', '11111'])), 6);
  });
  test('uniform squares count overlapping positions', () {
    expect(MaskUtil.uniformSquarePenalty(grid(['111', '111', '111'])), 12);
    expect(MaskUtil.uniformSquarePenalty(grid(['10', '01'])), 0);
  });
  test('finder cores require four internal light cells on either side', () {
    for (final sequence in ['00001011101', '10111010000', '000010111010000']) {
      expect(MaskUtil.finderPatternPenalty(grid([sequence])), 40);
      expect(MaskUtil.finderPatternPenalty(grid(sequence.split(''))), 40);
    }
    expect(MaskUtil.finderPatternPenalty(grid(['0001011101000'])), 0);
    expect(MaskUtil.finderPatternPenalty(grid(['1011101'])), 0);
  });
  test('dark proportion uses exact five-percent thresholds', () {
    for (final entry
        in {0: 100, 45: 10, 46: 0, 50: 0, 54: 0, 55: 10, 100: 100}.entries) {
      final row = '1' * entry.key + '0' * (100 - entry.key);
      expect(MaskUtil.darkBalancePenalty(grid([row])), entry.value);
    }
    expect(MaskUtil.darkBalancePenalty(ByteMatrix(0, 0)), 0);
  });
  test('all eight masks match fixed coordinate vectors', () {
    // In mask index order, independently calculated at the listed coordinates.
    final vectors = <(int, int), List<bool>>{
      (0, 0): [true, true, true, true, true, true, true, true],
      (1, 1): [true, false, false, false, true, false, true, false],
      (2, 3): [false, false, false, false, false, true, true, false],
      (3, 2): [false, true, true, false, true, true, true, false],
    };
    for (final entry in vectors.entries) {
      for (var mask = 0; mask < 8; mask++) {
        expect(MaskUtil.maskAppliesAt(mask, entry.key.$1, entry.key.$2),
            entry.value[mask],
            reason: '${entry.key}, mask $mask');
      }
    }
    expect(() => MaskUtil.maskAppliesAt(-1, 0, 0), throwsRangeError);
    expect(() => MaskUtil.maskAppliesAt(8, 0, 0), throwsRangeError);
  });
}
