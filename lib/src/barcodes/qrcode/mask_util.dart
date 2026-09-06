import 'byte_matrix.dart';
import 'qr_code.dart';

class MaskUtil {
  /// Apply mask penalty rule 1 and return the penalty.
  static int applyMaskPenaltyRule1(ByteMatrix matrix) {
    return _applyMaskPenaltyRule1Internal(matrix, true) +
        _applyMaskPenaltyRule1Internal(matrix, false);
  }

  /// Apply mask penalty rule 2 and return the penalty.
  static int applyMaskPenaltyRule2(ByteMatrix matrix) {
    int penalty = 0;
    List<List<int>> array = matrix.getArray();
    int width = matrix.getWidth();
    int height = matrix.getHeight();
    for (int y = 0; y < height - 1; ++y) {
      for (int x = 0; x < width - 1; ++x) {
        int value = array[y][x];
        if (value == array[y][x + 1] &&
            value == array[y + 1][x] &&
            value == array[y + 1][x + 1]) {
          penalty += 3;
        }
      }
    }
    return penalty;
  }

  /// Apply mask penalty rule 3 and return the penalty.
  static int applyMaskPenaltyRule3(ByteMatrix matrix) {
    int penalty = 0;
    List<List<int>> array = matrix.getArray();
    int width = matrix.getWidth();
    int height = matrix.getHeight();
    for (int y = 0; y < height; ++y) {
      for (int x = 0; x < width; ++x) {
        if (x + 6 < width &&
            array[y][x] == 1 &&
            array[y][x + 1] == 0 &&
            array[y][x + 2] == 1 &&
            array[y][x + 3] == 1 &&
            array[y][x + 4] == 1 &&
            array[y][x + 5] == 0 &&
            array[y][x + 6] == 1 &&
            ((x + 10 < width &&
                    array[y][x + 7] == 0 &&
                    array[y][x + 8] == 0 &&
                    array[y][x + 9] == 0 &&
                    array[y][x + 10] == 0) ||
                (x - 4 >= 0 &&
                    array[y][x - 1] == 0 &&
                    array[y][x - 2] == 0 &&
                    array[y][x - 3] == 0 &&
                    array[y][x - 4] == 0))) {
          penalty += 40;
        }
        if (y + 6 < height &&
            array[y][x] == 1 &&
            array[y + 1][x] == 0 &&
            array[y + 2][x] == 1 &&
            array[y + 3][x] == 1 &&
            array[y + 4][x] == 1 &&
            array[y + 5][x] == 0 &&
            array[y + 6][x] == 1 &&
            ((y + 10 < height &&
                    array[y + 7][x] == 0 &&
                    array[y + 8][x] == 0 &&
                    array[y + 9][x] == 0 &&
                    array[y + 10][x] == 0) ||
                (y - 4 >= 0 &&
                    array[y - 1][x] == 0 &&
                    array[y - 2][x] == 0 &&
                    array[y - 3][x] == 0 &&
                    array[y - 4][x] == 0))) {
          penalty += 40;
        }
      }
    }
    return penalty;
  }

  /// Apply mask penalty rule 4 and return the penalty.
  static int applyMaskPenaltyRule4(ByteMatrix matrix) {
    int numDarkCells = 0;
    List<List<int>> array = matrix.getArray();
    int width = matrix.getWidth();
    int height = matrix.getHeight();
    for (int y = 0; y < height; ++y) {
      for (int x = 0; x < width; ++x) {
        if (array[y][x] == 1) {
          numDarkCells += 1;
        }
      }
    }
    int numTotalCells = matrix.getHeight() * matrix.getWidth();
    double darkRatio = numDarkCells / numTotalCells;
    return (darkRatio * 100 - 50).abs().toInt() ~/ 5 * 10;
  }

  /// Return the mask bit for "getMaskPattern" at "x" and "y".
  static bool getDataMaskBit(int maskPattern, int x, int y) {
    if (!QRCode.isValidMaskPattern(maskPattern)) {
      throw ArgumentError("Invalid mask pattern");
    }
    int intermediate;
    int temp;
    switch (maskPattern) {
      case 0:
        intermediate = (y + x) & 0x1;
        break;
      case 1:
        intermediate = y & 0x1;
        break;
      case 2:
        intermediate = x % 3;
        break;
      case 3:
        intermediate = (y + x) % 3;
        break;
      case 4:
        intermediate = ((y >> 1) + (x ~/ 3)) & 0x1;
        break;
      case 5:
        temp = y * x;
        intermediate = (temp & 0x1) + (temp % 3);
        break;
      case 6:
        temp = y * x;
        intermediate = (((temp & 0x1) + (temp % 3)) & 0x1);
        break;
      case 7:
        temp = y * x;
        intermediate = (((temp % 3) + ((y + x) & 0x1)) & 0x1);
        break;
      default:
        throw ArgumentError("Invalid mask pattern: $maskPattern");
    }
    return intermediate == 0;
  }

  static int _applyMaskPenaltyRule1Internal(
      ByteMatrix matrix, bool isHorizontal) {
    int penalty = 0;
    int numSameBitCells = 0;
    int prevBit = -1;
    int iLimit = isHorizontal ? matrix.getHeight() : matrix.getWidth();
    int jLimit = isHorizontal ? matrix.getWidth() : matrix.getHeight();
    List<List<int>> array = matrix.getArray();
    for (int i = 0; i < iLimit; ++i) {
      for (int j = 0; j < jLimit; ++j) {
        int bit = isHorizontal ? array[i][j] : array[j][i];
        if (bit == prevBit) {
          numSameBitCells += 1;
          if (numSameBitCells == 5) {
            penalty += 3;
          } else {
            if (numSameBitCells > 5) {
              penalty += 1;
            }
          }
        } else {
          numSameBitCells = 1;
          prevBit = bit;
        }
      }
      numSameBitCells = 0;
    }
    return penalty;
  }
}
