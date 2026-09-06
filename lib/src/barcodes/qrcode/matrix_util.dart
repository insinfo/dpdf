import 'bit_vector.dart';
import 'byte_matrix.dart';
import 'error_correction_level.dart';
import 'mask_util.dart';
import 'version.dart';

/// Placement and polynomial checks for the fixed QR symbol geometry.
class CraftMatrixUtil {
  static void clearMatrix(CraftByteMatrix matrix) => matrix.clear(255);

  static void buildMatrix(
      CraftBitVector dataBits,
      CraftErrorCorrectionLevel ecLevel,
      int version,
      int maskPattern,
      CraftByteMatrix matrix) {
    final side = 17 + 4 * version;
    RangeError.checkValueInInterval(version, 1, 40, 'version');
    if (matrix.getWidth() != side || matrix.getHeight() != side) {
      throw ArgumentError('QR matrix dimensions disagree with its version');
    }
    clearMatrix(matrix);
    embedBasicPatterns(version, matrix);
    embedTypeInfo(ecLevel, maskPattern, matrix);
    maybeEmbedVersionInfo(version, matrix);
    embedDataBits(dataBits, maskPattern, matrix);
  }

  static void embedBasicPatterns(int version, CraftByteMatrix matrix) {
    embedPositionDetectionPatternsAndSeparators(matrix);
    maybeEmbedPositionAdjustmentPatterns(version, matrix);
    embedTimingPatterns(matrix);
    embedDarkDotAtLeftBottomCorner(matrix);
  }

  static int findMSBSet(int value) {
    RangeError.checkNotNegative(value, 'value');
    return value.bitLength;
  }

  static int calculateBCHCode(int value, int poly) {
    RangeError.checkNotNegative(value, 'value');
    if (poly < 2)
      throw ArgumentError.value(
          poly, 'poly', 'Polynomial needs a nonconstant term');
    final degree = poly.bitLength - 1;
    var remainder = 0;
    // Feed message coefficients followed by the zero augmentation.
    for (var position = value.bitLength + degree - 1;
        position >= 0;
        position--) {
      final incoming =
          position >= degree ? (value >> (position - degree)) & 1 : 0;
      remainder = (remainder << 1) | incoming;
      if ((remainder & (1 << degree)) != 0) remainder ^= poly;
    }
    return remainder;
  }

  static void makeTypeInfoBits(
      CraftErrorCorrectionLevel ecLevel, int maskPattern, CraftBitVector bits) {
    RangeError.checkValueInInterval(maskPattern, 0, 7, 'maskPattern');
    final value = ecLevel.bits * 8 + maskPattern;
    final protected = (value * 1024 + calculateBCHCode(value, 0x537)) ^ 0x5412;
    bits.appendBits(protected, 15);
  }

  static void makeVersionInfoBits(int version, CraftBitVector bits) {
    RangeError.checkValueInInterval(version, 1, 40, 'version');
    bits.appendBits(version * 4096 + calculateBCHCode(version, 0x1f25), 18);
  }

  static void embedTypeInfo(CraftErrorCorrectionLevel ecLevel, int maskPattern,
      CraftByteMatrix matrix) {
    final bits = CraftBitVector();
    makeTypeInfoBits(ecLevel, maskPattern, bits);
    final first = <(int, int)>[
      for (var y = 0; y <= 5; y++) (8, y),
      (8, 7),
      (8, 8),
      (7, 8),
      for (var x = 5; x >= 0; x--) (x, 8),
    ];
    final second = <(int, int)>[
      for (var x = matrix.getWidth() - 1; x >= matrix.getWidth() - 8; x--)
        (x, 8),
      for (var y = matrix.getHeight() - 7; y < matrix.getHeight(); y++) (8, y),
    ];
    for (final coordinates in [first, second]) {
      for (var index = 0; index < coordinates.length; index++) {
        final (x, y) = coordinates[index];
        matrix.set(x, y, bits.at(14 - index));
      }
    }
  }

  static void maybeEmbedVersionInfo(int version, CraftByteMatrix matrix) {
    if (version < 7) return;
    final bits = CraftBitVector();
    makeVersionInfoBits(version, bits);
    for (var index = 0; index < 18; index++) {
      final major = index ~/ 3;
      final minor = index % 3;
      final value = bits.at(17 - index);
      matrix.set(major, matrix.getHeight() - 11 + minor, value);
      matrix.set(matrix.getWidth() - 11 + minor, major, value);
    }
  }

  static void embedDataBits(
      CraftBitVector dataBits, int maskPattern, CraftByteMatrix matrix) {
    RangeError.checkValueInInterval(maskPattern, -1, 7, 'maskPattern');
    final columns = [
      for (var x = matrix.getWidth() - 1; x >= 0; x--)
        if (x != 6) x
    ];
    var consumed = 0;
    for (var stripe = 0; stripe + 1 < columns.length; stripe += 2) {
      final upwards = (stripe ~/ 2).isEven;
      for (var row = 0; row < matrix.getHeight(); row++) {
        final y = upwards ? matrix.getHeight() - 1 - row : row;
        for (final x in [columns[stripe], columns[stripe + 1]]) {
          if (matrix.get(x, y) != 255) continue;
          var value = consumed < dataBits.size() ? dataBits.at(consumed++) : 0;
          if (maskPattern >= 0 &&
              CraftMaskUtil.maskAppliesAt(maskPattern, x, y)) value ^= 1;
          matrix.set(x, y, value);
        }
      }
    }
    if (consumed < dataBits.size())
      throw ArgumentError('QR data exceeds the unreserved matrix cells');
  }

  static void _writeVacant(CraftByteMatrix matrix, int x, int y, int value) {
    if (matrix.get(x, y) != 255)
      throw StateError('QR pattern overlaps an occupied module at ($x, $y)');
    matrix.set(x, y, value);
  }

  static void _square(CraftByteMatrix matrix, int left, int top, int radius) {
    for (var position = 0;
        position < (radius * 2 + 1) * (radius * 2 + 1);
        position++) {
      final dx = position % (radius * 2 + 1) - radius;
      final dy = position ~/ (radius * 2 + 1) - radius;
      final distance = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
      _writeVacant(matrix, left + dx + radius, top + dy + radius,
          distance == radius - 1 ? 0 : 1);
    }
  }

  static void embedPositionDetectionPattern(
          int xStart, int yStart, CraftByteMatrix matrix) =>
      _square(matrix, xStart, yStart, 3);
  static void embedPositionAdjustmentPattern(
          int xStart, int yStart, CraftByteMatrix matrix) =>
      _square(matrix, xStart, yStart, 2);

  static void embedHorizontalSeparationPattern(
      int xStart, int yStart, CraftByteMatrix matrix) {
    for (var offset = 0; offset < 8; offset++) {
      _writeVacant(matrix, xStart + offset, yStart, 0);
    }
  }

  static void embedVerticalSeparationPattern(
      int xStart, int yStart, CraftByteMatrix matrix) {
    for (var offset = 0; offset < 7; offset++) {
      _writeVacant(matrix, xStart, yStart + offset, 0);
    }
  }

  static void embedPositionDetectionPatternsAndSeparators(
      CraftByteMatrix matrix) {
    for (final corner in [
      (0, 0),
      (matrix.getWidth() - 7, 0),
      (0, matrix.getHeight() - 7)
    ]) {
      final (left, top) = corner;
      embedPositionDetectionPattern(left, top, matrix);
      final start = left == 0 ? 0 : left - 1;
      final borderY = top == 0 ? 7 : top - 1;
      embedHorizontalSeparationPattern(start, borderY, matrix);
      embedVerticalSeparationPattern(left == 0 ? 7 : left - 1, top, matrix);
    }
  }

  static void maybeEmbedPositionAdjustmentPatterns(
      int version, CraftByteMatrix matrix) {
    final centers =
        CraftVersion.getVersionForNumber(version).getAlignmentPatternCenters();
    for (final x in centers) {
      for (final y in centers) {
        if (matrix.get(x, y) == 255)
          embedPositionAdjustmentPattern(x - 2, y - 2, matrix);
      }
    }
  }

  static void embedTimingPatterns(CraftByteMatrix matrix) {
    for (var coordinate = 8; coordinate < matrix.getWidth() - 8; coordinate++) {
      for (final cell in [(coordinate, 6), (6, coordinate)]) {
        final (x, y) = cell;
        final existing = matrix.get(x, y);
        if (existing == 255) {
          matrix.set(x, y, coordinate.isEven ? 1 : 0);
        } else if (existing != 0 && existing != 1) {
          throw StateError('QR timing path contains a nonbinary module');
        }
      }
    }
  }

  static void embedDarkDotAtLeftBottomCorner(CraftByteMatrix matrix) {
    final y = matrix.getHeight() - 8;
    if (matrix.get(8, y) == 0)
      throw StateError('QR fixed dark module was reserved as light');
    matrix.set(8, y, 1);
  }
}
