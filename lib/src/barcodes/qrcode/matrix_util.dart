import 'bit_vector.dart';
import 'byte_matrix.dart';
import 'error_correction_level.dart';
import 'mask_util.dart';
import 'qr_code.dart';

class MatrixUtil {
  static final List<List<int>> _POSITION_DETECTION_PATTERN = [
    [1, 1, 1, 1, 1, 1, 1],
    [1, 0, 0, 0, 0, 0, 1],
    [1, 0, 1, 1, 1, 0, 1],
    [1, 0, 1, 1, 1, 0, 1],
    [1, 0, 1, 1, 1, 0, 1],
    [1, 0, 0, 0, 0, 0, 1],
    [1, 1, 1, 1, 1, 1, 1]
  ];

  static final List<List<int>> _HORIZONTAL_SEPARATION_PATTERN = [
    [0, 0, 0, 0, 0, 0, 0, 0]
  ];

  static final List<List<int>> _VERTICAL_SEPARATION_PATTERN = [
    [0],
    [0],
    [0],
    [0],
    [0],
    [0],
    [0]
  ];

  static final List<List<int>> _POSITION_ADJUSTMENT_PATTERN = [
    [1, 1, 1, 1, 1],
    [1, 0, 0, 0, 1],
    [1, 0, 1, 0, 1],
    [1, 0, 0, 0, 1],
    [1, 1, 1, 1, 1]
  ];

  // From Appendix E. Table 1, JIS0510X:2004 (p 71). The table was double-checked by komatsu.
  static final List<List<int>> _POSITION_ADJUSTMENT_PATTERN_COORDINATE_TABLE = [
    [-1, -1, -1, -1, -1, -1, -1],
    [6, 18, -1, -1, -1, -1, -1],
    [6, 22, -1, -1, -1, -1, -1],
    [6, 26, -1, -1, -1, -1, -1],
    [6, 30, -1, -1, -1, -1, -1],
    [6, 34, -1, -1, -1, -1, -1],
    [6, 22, 38, -1, -1, -1, -1],
    [6, 24, 42, -1, -1, -1, -1],
    [6, 26, 46, -1, -1, -1, -1],
    [6, 28, 50, -1, -1, -1, -1],
    [6, 30, 54, -1, -1, -1, -1],
    [6, 32, 58, -1, -1, -1, -1],
    [6, 34, 62, -1, -1, -1, -1],
    [6, 26, 46, 66, -1, -1, -1],
    [6, 26, 48, 70, -1, -1, -1],
    [6, 26, 50, 74, -1, -1, -1],
    [6, 30, 54, 78, -1, -1, -1],
    [6, 30, 56, 82, -1, -1, -1],
    [6, 30, 58, 86, -1, -1, -1],
    [6, 34, 62, 90, -1, -1, -1],
    [6, 28, 50, 72, 94, -1, -1],
    [6, 26, 50, 74, 98, -1, -1],
    [6, 30, 54, 78, 102, -1, -1],
    [6, 28, 54, 80, 106, -1, -1],
    [6, 32, 58, 84, 110, -1, -1],
    [6, 30, 58, 86, 114, -1, -1],
    [6, 34, 62, 90, 118, -1, -1],
    [6, 26, 50, 74, 98, 122, -1],
    [6, 30, 54, 78, 102, 126, -1],
    [6, 26, 52, 78, 104, 130, -1],
    [6, 30, 56, 82, 108, 134, -1],
    [6, 34, 60, 86, 112, 138, -1],
    [6, 30, 58, 86, 114, 142, -1],
    [6, 34, 62, 90, 118, 146, -1],
    [6, 30, 54, 78, 102, 126, 150],
    [6, 24, 50, 76, 102, 128, 154],
    [6, 28, 54, 80, 106, 132, 158],
    [6, 32, 58, 84, 110, 136, 162],
    [6, 26, 54, 82, 110, 138, 166],
    [6, 30, 58, 86, 114, 142, 170]
  ];

  static final List<List<int>> _TYPE_INFO_COORDINATES = [
    [8, 0],
    [8, 1],
    [8, 2],
    [8, 3],
    [8, 4],
    [8, 5],
    [8, 7],
    [8, 8],
    [7, 8],
    [5, 8],
    [4, 8],
    [3, 8],
    [2, 8],
    [1, 8],
    [0, 8]
  ];

  static const int _VERSION_INFO_POLY = 0x1f25;
  static const int _TYPE_INFO_POLY = 0x537;
  static const int _TYPE_INFO_MASK_PATTERN = 0x5412;

  static void clearMatrix(ByteMatrix matrix) {
    matrix.clear(0xff);
  }

  static void buildMatrix(BitVector dataBits, ErrorCorrectionLevel ecLevel,
      int version, int maskPattern, ByteMatrix matrix) {
    clearMatrix(matrix);
    embedBasicPatterns(version, matrix);
    // Type information appear with any version.
    embedTypeInfo(ecLevel, maskPattern, matrix);
    // Version info appear if version >= 7.
    maybeEmbedVersionInfo(version, matrix);
    // Data should be embedded at end.
    embedDataBits(dataBits, maskPattern, matrix);
  }

  static void embedBasicPatterns(int version, ByteMatrix matrix) {
    // Let's get started with embedding big squares at corners.
    embedPositionDetectionPatternsAndSeparators(matrix);
    // Then, embed the dark dot at the left bottom corner.
    embedDarkDotAtLeftBottomCorner(matrix);
    // Position adjustment patterns appear if version >= 2.
    maybeEmbedPositionAdjustmentPatterns(version, matrix);
    // Timing patterns should be embedded after position adj. patterns.
    embedTimingPatterns(matrix);
  }

  static void embedTypeInfo(
      ErrorCorrectionLevel ecLevel, int maskPattern, ByteMatrix matrix) {
    BitVector typeInfoBits = BitVector();
    makeTypeInfoBits(ecLevel, maskPattern, typeInfoBits);
    for (int i = 0; i < typeInfoBits.size(); ++i) {
      // Place bits in LSB to MSB order.  LSB (least significant bit) is the last value in
      // "typeInfoBits".
      int bit = typeInfoBits.at(typeInfoBits.size() - 1 - i);
      // Type info bits at the left top corner. See 8.9 of JISX0510:2004 (p.46).
      int x1 = _TYPE_INFO_COORDINATES[i][0];
      int y1 = _TYPE_INFO_COORDINATES[i][1];
      matrix.set(x1, y1, bit);
      if (i < 8) {
        // Right top corner.
        int x2 = matrix.getWidth() - i - 1;
        int y2 = 8;
        matrix.set(x2, y2, bit);
      } else {
        // Left bottom corner.
        int x2 = 8;
        int y2 = matrix.getHeight() - 7 + (i - 8);
        matrix.set(x2, y2, bit);
      }
    }
  }

  static void maybeEmbedVersionInfo(int version, ByteMatrix matrix) {
    // Version info is necessary if version >= 7.
    if (version < 7) {
      // Don't need version info.
      return;
    }
    BitVector versionInfoBits = BitVector();
    makeVersionInfoBits(version, versionInfoBits);
    // It will decrease from 17 to 0.
    int bitIndex = 6 * 3 - 1;
    for (int i = 0; i < 6; ++i) {
      for (int j = 0; j < 3; ++j) {
        // Place bits in LSB (least significant bit) to MSB order.
        int bit = versionInfoBits.at(bitIndex);
        bitIndex--;
        // Left bottom corner.
        matrix.set(i, matrix.getHeight() - 11 + j, bit);
        // Right bottom corner.
        matrix.set(matrix.getHeight() - 11 + j, i, bit);
      }
    }
  }

  static void embedDataBits(
      BitVector dataBits, int maskPattern, ByteMatrix matrix) {
    int bitIndex = 0;
    int direction = -1;
    // Start from the right bottom cell.
    int x = matrix.getWidth() - 1;
    int y = matrix.getHeight() - 1;
    while (x > 0) {
      // Skip the vertical timing pattern.
      if (x == 6) {
        x -= 1;
      }
      while (y >= 0 && y < matrix.getHeight()) {
        for (int i = 0; i < 2; ++i) {
          int xx = x - i;
          // Skip the cell if it's not empty.
          if (!_isEmpty(matrix.get(xx, y))) {
            continue;
          }
          int bit;
          if (bitIndex < dataBits.size()) {
            bit = dataBits.at(bitIndex);
            ++bitIndex;
          } else {
            // Padding bit. If there is no bit left, we'll fill the left cells with 0, as described
            // in 8.4.9 of JISX0510:2004 (p. 24).
            bit = 0;
          }
          // Skip masking if mask_pattern is -1.
          if (maskPattern != -1) {
            if (MaskUtil.getDataMaskBit(maskPattern, xx, y)) {
              bit ^= 0x1;
            }
          }
          matrix.set(xx, y, bit);
        }
        y += direction;
      }
      // Reverse the direction.
      direction = -direction;
      y += direction;
      // Move to the left.
      x -= 2;
    }
    // All bits should be consumed.
    if (bitIndex != dataBits.size()) {
      throw Exception(
          "Not all bits consumed: $bitIndex/${dataBits.size()}"); // WriterException
    }
  }

  static int findMSBSet(int value) {
    int numDigits = 0;
    while (value != 0) {
      value = value >> 1;
      ++numDigits;
    }
    return numDigits;
  }

  static int calculateBCHCode(int value, int poly) {
    // If poly is "1 1111 0010 0101" (version info poly), msbSetInPoly is 13. We'll subtract 1
    // from 13 to make it 12.
    int msbSetInPoly = findMSBSet(poly);
    value <<= msbSetInPoly - 1;
    // Do the division business using exclusive-or operations.
    while (findMSBSet(value) >= msbSetInPoly) {
      value ^= poly << (findMSBSet(value) - msbSetInPoly);
    }
    // Now the "value" is the remainder (i.e. the BCH code)
    return value;
  }

  static void makeTypeInfoBits(
      ErrorCorrectionLevel ecLevel, int maskPattern, BitVector bits) {
    if (!QRCode.isValidMaskPattern(maskPattern)) {
      throw Exception("Invalid mask pattern"); // WriterException
    }
    int typeInfo = (ecLevel.bits << 3) | maskPattern;
    bits.appendBits(typeInfo, 5);
    int bchCode = calculateBCHCode(typeInfo, _TYPE_INFO_POLY);
    bits.appendBits(bchCode, 10);
    BitVector maskBits = BitVector();
    maskBits.appendBits(_TYPE_INFO_MASK_PATTERN, 15);
    bits.xor(maskBits);
    // Just in case.
    if (bits.size() != 15) {
      throw Exception("should not happen but we got: ${bits.size()}");
    }
  }

  static void makeVersionInfoBits(int version, BitVector bits) {
    bits.appendBits(version, 6);
    int bchCode = calculateBCHCode(version, _VERSION_INFO_POLY);
    bits.appendBits(bchCode, 12);
    // Just in case.
    if (bits.size() != 18) {
      throw Exception("should not happen but we got: ${bits.size()}");
    }
  }

  static bool _isEmpty(int value) {
    return value ==
        0xff; // -1 byte is 0xff in Dart Uint8List access? No, matrix stores int.
    // The C# code uses byte matrix but 0xff.
    // ByteMatrix in Dart uses Int32List or similar?
    // Let's check ByteMatrix implementation.
  }

  static bool _isValidValue(int value) {
    return (value == 0xff || // Empty
        value == 0 || // Light (white)
        value == 1); // Dark (black)
  }

  static void embedTimingPatterns(ByteMatrix matrix) {
    for (int i = 8; i < matrix.getWidth() - 8; ++i) {
      int bit = (i + 1) % 2;
      // Horizontal line.
      if (!_isValidValue(matrix.get(i, 6))) {
        throw Exception(); // WriterException
      }
      if (_isEmpty(matrix.get(i, 6))) {
        matrix.set(i, 6, bit);
      }
      // Vertical line.
      if (!_isValidValue(matrix.get(6, i))) {
        throw Exception(); // WriterException
      }
      if (_isEmpty(matrix.get(6, i))) {
        matrix.set(6, i, bit);
      }
    }
  }

  static void embedDarkDotAtLeftBottomCorner(ByteMatrix matrix) {
    if (matrix.get(8, matrix.getHeight() - 8) == 0) {
      throw Exception(); // WriterException
    }
    matrix.set(8, matrix.getHeight() - 8, 1);
  }

  static void embedHorizontalSeparationPattern(
      int xStart, int yStart, ByteMatrix matrix) {
    if (_HORIZONTAL_SEPARATION_PATTERN[0].length != 8 ||
        _HORIZONTAL_SEPARATION_PATTERN.length != 1) {
      throw Exception("Bad horizontal separation pattern");
    }
    for (int x = 0; x < 8; ++x) {
      if (!_isEmpty(matrix.get(xStart + x, yStart))) {
        throw Exception();
      }
      matrix.set(xStart + x, yStart, _HORIZONTAL_SEPARATION_PATTERN[0][x]);
    }
  }

  static void embedVerticalSeparationPattern(
      int xStart, int yStart, ByteMatrix matrix) {
    if (_VERTICAL_SEPARATION_PATTERN[0].length != 1 ||
        _VERTICAL_SEPARATION_PATTERN.length != 7) {
      throw Exception("Bad vertical separation pattern");
    }
    for (int y = 0; y < 7; ++y) {
      if (!_isEmpty(matrix.get(xStart, yStart + y))) {
        throw Exception();
      }
      matrix.set(xStart, yStart + y, _VERTICAL_SEPARATION_PATTERN[y][0]);
    }
  }

  static void embedPositionAdjustmentPattern(
      int xStart, int yStart, ByteMatrix matrix) {
    if (_POSITION_ADJUSTMENT_PATTERN[0].length != 5 ||
        _POSITION_ADJUSTMENT_PATTERN.length != 5) {
      throw Exception("Bad position adjustment");
    }
    for (int y = 0; y < 5; ++y) {
      for (int x = 0; x < 5; ++x) {
        if (!_isEmpty(matrix.get(xStart + x, yStart + y))) {
          throw Exception();
        }
        matrix.set(xStart + x, yStart + y, _POSITION_ADJUSTMENT_PATTERN[y][x]);
      }
    }
  }

  static void embedPositionDetectionPattern(
      int xStart, int yStart, ByteMatrix matrix) {
    if (_POSITION_DETECTION_PATTERN[0].length != 7 ||
        _POSITION_DETECTION_PATTERN.length != 7) {
      throw Exception("Bad position detection pattern");
    }
    for (int y = 0; y < 7; ++y) {
      for (int x = 0; x < 7; ++x) {
        if (!_isEmpty(matrix.get(xStart + x, yStart + y))) {
          throw Exception();
        }
        matrix.set(xStart + x, yStart + y, _POSITION_DETECTION_PATTERN[y][x]);
      }
    }
  }

  static void embedPositionDetectionPatternsAndSeparators(ByteMatrix matrix) {
    int pdpWidth = _POSITION_DETECTION_PATTERN[0].length;
    // Left top corner.
    embedPositionDetectionPattern(0, 0, matrix);
    // Right top corner.
    embedPositionDetectionPattern(matrix.getWidth() - pdpWidth, 0, matrix);
    // Left bottom corner.
    embedPositionDetectionPattern(0, matrix.getWidth() - pdpWidth, matrix);
    // Embed horizontal separation patterns around the squares.
    int hspWidth = _HORIZONTAL_SEPARATION_PATTERN[0].length;
    // Left top corner.
    embedHorizontalSeparationPattern(0, hspWidth - 1, matrix);
    // Right top corner.
    embedHorizontalSeparationPattern(
        matrix.getWidth() - hspWidth, hspWidth - 1, matrix);
    // Left bottom corner.
    embedHorizontalSeparationPattern(0, matrix.getWidth() - hspWidth, matrix);
    // Embed vertical separation patterns around the squares.
    int vspSize = _VERTICAL_SEPARATION_PATTERN.length;
    // Left top corner.
    embedVerticalSeparationPattern(vspSize, 0, matrix);
    // Right top corner.
    embedVerticalSeparationPattern(matrix.getHeight() - vspSize - 1, 0, matrix);
    // Left bottom corner.
    embedVerticalSeparationPattern(
        vspSize, matrix.getHeight() - vspSize, matrix);
  }

  static void maybeEmbedPositionAdjustmentPatterns(
      int version, ByteMatrix matrix) {
    if (version < 2) {
      return;
    }
    int index = version - 1;
    List<int> coordinates =
        _POSITION_ADJUSTMENT_PATTERN_COORDINATE_TABLE[index];
    int numCoordinates = coordinates.length;
    for (int i = 0; i < numCoordinates; ++i) {
      for (int j = 0; j < numCoordinates; ++j) {
        int y = coordinates[i];
        int x = coordinates[j];
        if (x == -1 || y == -1) {
          continue;
        }
        if (_isEmpty(matrix.get(x, y))) {
          embedPositionAdjustmentPattern(x - 2, y - 2, matrix);
        }
      }
    }
  }
}
