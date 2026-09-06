import 'byte_matrix.dart';

/// Scores completed QR module grids and evaluates the eight QR mask formulas.
class CraftMaskUtil {
  static Iterable<List<int>> _scanLines(CraftByteMatrix grid) sync* {
    yield* grid.getArray();
    for (var column = 0; column < grid.getWidth(); column++) {
      yield List.generate(grid.getHeight(), (row) => grid.get(column, row));
    }
  }

  /// A monochrome run of length n >= 5 contributes n - 2.
  static int repeatedRunPenalty(CraftByteMatrix matrix) {
    var score = 0;
    for (final line in _scanLines(matrix)) {
      var start = 0;
      while (start < line.length) {
        var end = start + 1;
        while (end < line.length && line[end] == line[start]) {
          end++;
        }
        final length = end - start;
        if (length >= 5) score += length - 2;
        start = end;
      }
    }
    return score;
  }

  /// Every uniform 2-by-2 square contributes three, including overlaps.
  static int uniformSquarePenalty(CraftByteMatrix matrix) {
    var squares = 0;
    for (var row = 1; row < matrix.getHeight(); row++) {
      for (var column = 1; column < matrix.getWidth(); column++) {
        final corners = {
          matrix.get(column - 1, row - 1),
          matrix.get(column, row - 1),
          matrix.get(column - 1, row),
          matrix.get(column, row),
        };
        if (corners.length == 1) squares++;
      }
    }
    return squares * 3;
  }

  /// Finder-like 1011101 cores need four light modules on either side.
  /// A core contributes once even when both sides provide that separation.
  static int finderPatternPenalty(CraftByteMatrix matrix) {
    var occurrences = 0;
    for (final line in _scanLines(matrix)) {
      var window = 0;
      for (var end = 0; end < line.length; end++) {
        window = ((window << 1) | line[end]) & 127;
        if (end < 6 || window != 93) continue;
        final start = end - 6;
        bool lightSpan(int first) =>
            first >= 0 &&
            first + 4 <= line.length &&
            line.skip(first).take(4).every((module) => module == 0);
        if (lightSpan(start - 4) || lightSpan(end + 1)) occurrences++;
      }
    }
    return occurrences * 40;
  }

  /// Each complete five percentage points away from half dark costs ten.
  static int darkBalancePenalty(CraftByteMatrix matrix) {
    final area = matrix.getWidth() * matrix.getHeight();
    if (area == 0) return 0;
    final dark = matrix.getArray().fold<int>(
        0, (count, row) => count + row.where((value) => value == 1).length);
    return ((2 * dark - area).abs() * 10 ~/ area) * 10;
  }

  /// Coordinates use x for columns and y for rows, starting at zero.
  static bool maskAppliesAt(int maskPattern, int x, int y) {
    return switch (maskPattern) {
      0 => (x + y).isEven,
      1 => y.isEven,
      2 => x % 3 == 0,
      3 => (x + y) % 3 == 0,
      4 => (y ~/ 2 + x ~/ 3).isEven,
      5 => (x * y) % 2 + (x * y) % 3 == 0,
      6 => ((x * y) % 2 + (x * y) % 3).isEven,
      7 => ((x * y) % 3 + (x + y) % 2).isEven,
      _ => throw RangeError.range(maskPattern, 0, 7, 'maskPattern',
          'QR masking requires an index from zero through seven'),
    };
  }
}
