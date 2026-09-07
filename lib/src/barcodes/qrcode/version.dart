import 'bit_matrix.dart';
import 'error_correction_level.dart';

/// Encapsulates the parameters for one error-correction block in one symbol version.
class ECB {
  final int _count;
  final int _dataCodewords;

  ECB(this._count, this._dataCodewords);

  int getCount() {
    return _count;
  }

  int getDataCodewords() {
    return _dataCodewords;
  }
}

/// Encapsulates a set of error-correction blocks in one symbol version.
class ECBlocks {
  final int _ecCodewordsPerBlock;
  late List<ECB> _ecBlocks;

  ECBlocks(this._ecCodewordsPerBlock, [ECB? ecBlocks1, ECB? ecBlocks2]) {
    _ecBlocks = [
      if (ecBlocks1 != null) ecBlocks1,
      if (ecBlocks2 != null) ecBlocks2
    ];
    if (_ecBlocks.isEmpty) {
      throw ArgumentError('At least one QR block group is required');
    }
  }

  int getECCodewordsPerBlock() {
    return _ecCodewordsPerBlock;
  }

  int getNumBlocks() {
    return _ecBlocks.fold(0, (count, block) => count + block.getCount());
  }

  int getTotalECCodewords() {
    return _ecCodewordsPerBlock * getNumBlocks();
  }

  List<ECB> getECBlocks() {
    return _ecBlocks;
  }
}

/// See ISO 18004:2006 Annex D.
class CraftVersion {
  static final List<int> VERSION_DECODE_INFO = [
    0x07C94,
    0x085BC,
    0x09A99,
    0x0A4D3,
    0x0BBF6,
    0x0C762,
    0x0D847,
    0x0E60D,
    0x0F928,
    0x10B78,
    0x1145D,
    0x12A17,
    0x13532,
    0x149A6,
    0x15683,
    0x168C9,
    0x177EC,
    0x18EC4,
    0x191E1,
    0x1AFAB,
    0x1B08E,
    0x1CC1A,
    0x1D33F,
    0x1ED75,
    0x1F250,
    0x209D5,
    0x216F0,
    0x228BA,
    0x2379F,
    0x24B0B,
    0x2542E,
    0x26A64,
    0x27541,
    0x28C69
  ];

  static final List<CraftVersion> VERSIONS = _buildVersions();

  final int _versionNumber;
  final List<int> _alignmentPatternCenters;
  final List<ECBlocks> _ecBlocks;
  late int _totalCodewords;

  CraftVersion(
      this._versionNumber,
      List<int> alignmentPatternCenters,
      ECBlocks ecBlocks1,
      ECBlocks ecBlocks2,
      ECBlocks ecBlocks3,
      ECBlocks ecBlocks4)
      : _alignmentPatternCenters = List.from(alignmentPatternCenters),
        _ecBlocks = [ecBlocks1, ecBlocks2, ecBlocks3, ecBlocks4] {
    _totalCodewords = ecBlocks1.getTotalECCodewords() +
        ecBlocks1.getECBlocks().fold(0,
            (sum, group) => sum + group.getCount() * group.getDataCodewords());
  }

  int getVersionNumber() {
    return _versionNumber;
  }

  List<int> getAlignmentPatternCenters() {
    return _alignmentPatternCenters;
  }

  int getTotalCodewords() {
    return _totalCodewords;
  }

  int getDimensionForVersion() {
    return 17 + 4 * _versionNumber;
  }

  ECBlocks getECBlocksForLevel(CraftErrorCorrectionLevel ecLevel) {
    return _ecBlocks[ecLevel.ordinal];
  }

  /// Resolves the version encoded by a square symbol's side length.
  static CraftVersion getProvisionalVersionForDimension(int dimension) {
    if (dimension < 21 || dimension > 177 || (dimension - 17) % 4 != 0) {
      throw ArgumentError.value(
          dimension, 'dimension', 'Not a QR symbol side length');
    }
    return getVersionForNumber((dimension - 17) ~/ 4);
  }

  static CraftVersion getVersionForNumber(int versionNumber) {
    RangeError.checkValueInInterval(versionNumber, 1, 40, 'versionNumber');
    return VERSIONS.elementAt(versionNumber - 1);
  }

  static CraftVersion? decodeVersionInformation(int versionBits) {
    if (versionBits < 0 || versionBits >= 1 << 18) return null;
    // Valid version words have disjoint radius-three Hamming neighborhoods.
    for (var number = 7; number <= 40; number++) {
      var remainder = number << 12;
      for (var degree = 17; degree >= 12; degree--) {
        if ((remainder & (1 << degree)) != 0) {
          remainder ^= 0x1f25 << (degree - 12);
        }
      }
      var difference = versionBits ^ ((number << 12) | remainder);
      var errors = 0;
      while (difference != 0 && errors < 4) {
        difference &= difference - 1;
        errors++;
      }
      if (errors <= 3) return getVersionForNumber(number);
    }
    return null;
  }

  CraftBitMatrix buildFunctionPattern() {
    final side = getDimensionForVersion();
    final result = CraftBitMatrix(side);
    final centers = _alignmentPatternCenters;
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        var reserved = (x < 9 && y < 9) ||
            (x >= side - 8 && y < 9) ||
            (y >= side - 8 && x < 9) ||
            x == 6 ||
            y == 6;
        if (_versionNumber >= 7) {
          reserved |= (x < 6 && y >= side - 11) || (y < 6 && x >= side - 11);
        }
        if (!reserved) {
          for (final centerY in centers) {
            if ((y - centerY).abs() > 2) continue;
            for (final centerX in centers) {
              final finderOverlap =
                  (centerX == 6 && (centerY == 6 || centerY == side - 7)) ||
                      (centerY == 6 && centerX == side - 7);
              if (!finderOverlap && (x - centerX).abs() <= 2) reserved = true;
            }
          }
        }
        if (reserved) result.set(x, y);
      }
    }
    return result;
  }

  @override
  String toString() {
    return _versionNumber.toString();
  }

  static List<CraftVersion> _buildVersions() {
    // Factual QR capacity and alignment parameters for versions 1 through 40.
    return [
      CraftVersion(1, [], ECBlocks(7, ECB(1, 19)), ECBlocks(10, ECB(1, 16)),
          ECBlocks(13, ECB(1, 13)), ECBlocks(17, ECB(1, 9))),
      CraftVersion(
          2,
          [6, 18],
          ECBlocks(10, ECB(1, 34)),
          ECBlocks(16, ECB(1, 28)),
          ECBlocks(22, ECB(1, 22)),
          ECBlocks(28, ECB(1, 16))),
      CraftVersion(
          3,
          [6, 22],
          ECBlocks(15, ECB(1, 55)),
          ECBlocks(26, ECB(1, 44)),
          ECBlocks(18, ECB(2, 17)),
          ECBlocks(22, ECB(2, 13))),
      CraftVersion(
          4,
          [6, 26],
          ECBlocks(20, ECB(1, 80)),
          ECBlocks(18, ECB(2, 32)),
          ECBlocks(26, ECB(2, 24)),
          ECBlocks(16, ECB(4, 9))),
      CraftVersion(
          5,
          [6, 30],
          ECBlocks(26, ECB(1, 108)),
          ECBlocks(24, ECB(2, 43)),
          ECBlocks(18, ECB(2, 15), ECB(2, 16)),
          ECBlocks(22, ECB(2, 11), ECB(2, 12))),
      CraftVersion(
          6,
          [6, 34],
          ECBlocks(18, ECB(2, 68)),
          ECBlocks(16, ECB(4, 27)),
          ECBlocks(24, ECB(4, 19)),
          ECBlocks(28, ECB(4, 15))),
      CraftVersion(
          7,
          [6, 22, 38],
          ECBlocks(20, ECB(2, 78)),
          ECBlocks(18, ECB(4, 31)),
          ECBlocks(18, ECB(2, 14), ECB(4, 15)),
          ECBlocks(26, ECB(4, 13), ECB(1, 14))),
      CraftVersion(
          8,
          [6, 24, 42],
          ECBlocks(24, ECB(2, 97)),
          ECBlocks(22, ECB(2, 38), ECB(2, 39)),
          ECBlocks(22, ECB(4, 18), ECB(2, 19)),
          ECBlocks(26, ECB(4, 14), ECB(2, 15))),
      CraftVersion(
          9,
          [6, 26, 46],
          ECBlocks(30, ECB(2, 116)),
          ECBlocks(22, ECB(3, 36), ECB(2, 37)),
          ECBlocks(20, ECB(4, 16), ECB(4, 17)),
          ECBlocks(24, ECB(4, 12), ECB(4, 13))),
      CraftVersion(
          10,
          [6, 28, 50],
          ECBlocks(18, ECB(2, 68), ECB(2, 69)),
          ECBlocks(26, ECB(4, 43), ECB(1, 44)),
          ECBlocks(24, ECB(6, 19), ECB(2, 20)),
          ECBlocks(28, ECB(6, 15), ECB(2, 16))),
      CraftVersion(
          11,
          [6, 30, 54],
          ECBlocks(20, ECB(4, 81)),
          ECBlocks(30, ECB(1, 50), ECB(4, 51)),
          ECBlocks(28, ECB(4, 22), ECB(4, 23)),
          ECBlocks(24, ECB(3, 12), ECB(8, 13))),
      CraftVersion(
          12,
          [6, 32, 58],
          ECBlocks(24, ECB(2, 92), ECB(2, 93)),
          ECBlocks(22, ECB(6, 36), ECB(2, 37)),
          ECBlocks(26, ECB(4, 20), ECB(6, 21)),
          ECBlocks(28, ECB(7, 14), ECB(4, 15))),
      CraftVersion(
          13,
          [6, 34, 62],
          ECBlocks(26, ECB(4, 107)),
          ECBlocks(22, ECB(8, 37), ECB(1, 38)),
          ECBlocks(24, ECB(8, 20), ECB(4, 21)),
          ECBlocks(22, ECB(12, 11), ECB(4, 12))),
      CraftVersion(
          14,
          [6, 26, 46, 66],
          ECBlocks(30, ECB(3, 115), ECB(1, 116)),
          ECBlocks(24, ECB(4, 40), ECB(5, 41)),
          ECBlocks(20, ECB(11, 16), ECB(5, 17)),
          ECBlocks(24, ECB(11, 12), ECB(5, 13))),
      CraftVersion(
          15,
          [6, 26, 48, 70],
          ECBlocks(22, ECB(5, 87), ECB(1, 88)),
          ECBlocks(24, ECB(5, 41), ECB(5, 42)),
          ECBlocks(30, ECB(5, 24), ECB(7, 25)),
          ECBlocks(24, ECB(11, 12), ECB(7, 13))),
      CraftVersion(
          16,
          [6, 26, 50, 74],
          ECBlocks(24, ECB(5, 98), ECB(1, 99)),
          ECBlocks(28, ECB(7, 45), ECB(3, 46)),
          ECBlocks(24, ECB(15, 19), ECB(2, 20)),
          ECBlocks(30, ECB(3, 15), ECB(13, 16))),
      CraftVersion(
          17,
          [6, 30, 54, 78],
          ECBlocks(28, ECB(1, 107), ECB(5, 108)),
          ECBlocks(28, ECB(10, 46), ECB(1, 47)),
          ECBlocks(28, ECB(1, 22), ECB(15, 23)),
          ECBlocks(28, ECB(2, 14), ECB(17, 15))),
      CraftVersion(
          18,
          [6, 30, 56, 82],
          ECBlocks(30, ECB(5, 120), ECB(1, 121)),
          ECBlocks(26, ECB(9, 43), ECB(4, 44)),
          ECBlocks(28, ECB(17, 22), ECB(1, 23)),
          ECBlocks(28, ECB(2, 14), ECB(19, 15))),
      CraftVersion(
          19,
          [6, 30, 58, 86],
          ECBlocks(28, ECB(3, 113), ECB(4, 114)),
          ECBlocks(26, ECB(3, 44), ECB(11, 45)),
          ECBlocks(26, ECB(17, 21), ECB(4, 22)),
          ECBlocks(26, ECB(9, 13), ECB(16, 14))),
      CraftVersion(
          20,
          [6, 34, 62, 90],
          ECBlocks(28, ECB(3, 107), ECB(5, 108)),
          ECBlocks(26, ECB(3, 41), ECB(13, 42)),
          ECBlocks(30, ECB(15, 24), ECB(5, 25)),
          ECBlocks(28, ECB(15, 15), ECB(10, 16))),
      CraftVersion(
          21,
          [6, 28, 50, 72, 94],
          ECBlocks(28, ECB(4, 116), ECB(4, 117)),
          ECBlocks(26, ECB(17, 42)),
          ECBlocks(28, ECB(17, 22), ECB(6, 23)),
          ECBlocks(30, ECB(19, 16), ECB(6, 17))),
      CraftVersion(
          22,
          [6, 26, 50, 74, 98],
          ECBlocks(28, ECB(2, 111), ECB(7, 112)),
          ECBlocks(28, ECB(17, 46)),
          ECBlocks(30, ECB(7, 24), ECB(16, 25)),
          ECBlocks(24, ECB(34, 13))),
      CraftVersion(
          23,
          [6, 30, 54, 74, 102],
          ECBlocks(30, ECB(4, 121), ECB(5, 122)),
          ECBlocks(28, ECB(4, 47), ECB(14, 48)),
          ECBlocks(30, ECB(11, 24), ECB(14, 25)),
          ECBlocks(30, ECB(16, 15), ECB(14, 16))),
      CraftVersion(
          24,
          [6, 28, 54, 80, 106],
          ECBlocks(30, ECB(6, 117), ECB(4, 118)),
          ECBlocks(28, ECB(6, 45), ECB(14, 46)),
          ECBlocks(30, ECB(11, 24), ECB(16, 25)),
          ECBlocks(30, ECB(30, 16), ECB(2, 17))),
      CraftVersion(
          25,
          [6, 32, 58, 84, 110],
          ECBlocks(26, ECB(8, 106), ECB(4, 107)),
          ECBlocks(28, ECB(8, 47), ECB(13, 48)),
          ECBlocks(30, ECB(7, 24), ECB(22, 25)),
          ECBlocks(30, ECB(22, 15), ECB(13, 16))),
      CraftVersion(
          26,
          [6, 30, 58, 86, 114],
          ECBlocks(28, ECB(10, 114), ECB(2, 115)),
          ECBlocks(28, ECB(19, 46), ECB(4, 47)),
          ECBlocks(28, ECB(28, 22), ECB(6, 23)),
          ECBlocks(30, ECB(33, 16), ECB(4, 17))),
      CraftVersion(
          27,
          [6, 34, 62, 90, 118],
          ECBlocks(30, ECB(8, 122), ECB(4, 123)),
          ECBlocks(28, ECB(22, 45), ECB(3, 46)),
          ECBlocks(30, ECB(8, 23), ECB(26, 24)),
          ECBlocks(30, ECB(12, 15), ECB(28, 16))),
      CraftVersion(
          28,
          [6, 26, 50, 74, 98, 122],
          ECBlocks(30, ECB(3, 117), ECB(10, 118)),
          ECBlocks(28, ECB(3, 45), ECB(23, 46)),
          ECBlocks(30, ECB(4, 24), ECB(31, 25)),
          ECBlocks(30, ECB(11, 15), ECB(31, 16))),
      CraftVersion(
          29,
          [6, 30, 54, 78, 102, 126],
          ECBlocks(30, ECB(7, 116), ECB(7, 117)),
          ECBlocks(28, ECB(21, 45), ECB(7, 46)),
          ECBlocks(30, ECB(1, 23), ECB(37, 24)),
          ECBlocks(30, ECB(19, 15), ECB(26, 16))),
      CraftVersion(
          30,
          [6, 26, 52, 78, 104, 130],
          ECBlocks(30, ECB(5, 115), ECB(10, 116)),
          ECBlocks(28, ECB(19, 47), ECB(10, 48)),
          ECBlocks(30, ECB(15, 24), ECB(25, 25)),
          ECBlocks(30, ECB(23, 15), ECB(25, 16))),
      CraftVersion(
          31,
          [6, 30, 56, 82, 108, 134],
          ECBlocks(30, ECB(13, 115), ECB(3, 116)),
          ECBlocks(28, ECB(2, 46), ECB(29, 47)),
          ECBlocks(30, ECB(42, 24), ECB(1, 25)),
          ECBlocks(30, ECB(23, 15), ECB(28, 16))),
      CraftVersion(
          32,
          [6, 34, 60, 86, 112, 138],
          ECBlocks(30, ECB(17, 115)),
          ECBlocks(28, ECB(10, 46), ECB(23, 47)),
          ECBlocks(30, ECB(10, 24), ECB(35, 25)),
          ECBlocks(30, ECB(19, 15), ECB(35, 16))),
      CraftVersion(
          33,
          [6, 30, 58, 86, 114, 142],
          ECBlocks(30, ECB(17, 115), ECB(1, 116)),
          ECBlocks(28, ECB(14, 46), ECB(21, 47)),
          ECBlocks(30, ECB(29, 24), ECB(19, 25)),
          ECBlocks(30, ECB(11, 15), ECB(46, 16))),
      CraftVersion(
          34,
          [6, 34, 62, 90, 118, 146],
          ECBlocks(30, ECB(13, 115), ECB(6, 116)),
          ECBlocks(28, ECB(14, 46), ECB(23, 47)),
          ECBlocks(30, ECB(44, 24), ECB(7, 25)),
          ECBlocks(30, ECB(59, 16), ECB(1, 17))),
      CraftVersion(
          35,
          [6, 30, 54, 78, 102, 126, 150],
          ECBlocks(30, ECB(12, 121), ECB(7, 122)),
          ECBlocks(28, ECB(12, 47), ECB(26, 48)),
          ECBlocks(30, ECB(39, 24), ECB(14, 25)),
          ECBlocks(30, ECB(22, 15), ECB(41, 16))),
      CraftVersion(
          36,
          [6, 24, 50, 76, 102, 128, 154],
          ECBlocks(30, ECB(6, 121), ECB(14, 122)),
          ECBlocks(28, ECB(6, 47), ECB(34, 48)),
          ECBlocks(30, ECB(46, 24), ECB(10, 25)),
          ECBlocks(30, ECB(2, 15), ECB(64, 16))),
      CraftVersion(
          37,
          [6, 28, 54, 80, 106, 132, 158],
          ECBlocks(30, ECB(17, 122), ECB(4, 123)),
          ECBlocks(28, ECB(29, 46), ECB(14, 47)),
          ECBlocks(30, ECB(49, 24), ECB(10, 25)),
          ECBlocks(30, ECB(24, 15), ECB(46, 16))),
      CraftVersion(
          38,
          [6, 32, 58, 84, 110, 136, 162],
          ECBlocks(30, ECB(4, 122), ECB(18, 123)),
          ECBlocks(28, ECB(13, 46), ECB(32, 47)),
          ECBlocks(30, ECB(48, 24), ECB(14, 25)),
          ECBlocks(30, ECB(42, 15), ECB(32, 16))),
      CraftVersion(
          39,
          [6, 26, 54, 82, 110, 138, 166],
          ECBlocks(30, ECB(20, 117), ECB(4, 118)),
          ECBlocks(28, ECB(40, 47), ECB(7, 48)),
          ECBlocks(30, ECB(43, 24), ECB(22, 25)),
          ECBlocks(30, ECB(10, 15), ECB(67, 16))),
      CraftVersion(
          40,
          [6, 30, 58, 86, 114, 142, 170],
          ECBlocks(30, ECB(19, 118), ECB(6, 119)),
          ECBlocks(28, ECB(18, 47), ECB(31, 48)),
          ECBlocks(30, ECB(34, 24), ECB(34, 25)),
          ECBlocks(30, ECB(20, 15), ECB(61, 16))),
    ];
  }
}
