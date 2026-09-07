import 'package:dpdf/src/barcodes/qrcode/bit_vector.dart';
import 'package:dpdf/src/barcodes/qrcode/byte_matrix.dart';
import 'package:dpdf/src/barcodes/qrcode/error_correction_level.dart';
import 'package:dpdf/src/barcodes/qrcode/matrix_util.dart';
import 'package:dpdf/src/barcodes/qrcode/version.dart';
import 'package:test/test.dart';

int asNumber(CraftBitVector bits) {
  var value = 0;
  for (var i = 0; i < bits.size(); i++) {
    value = value * 2 + bits.at(i);
  }
  return value;
}

void main() {
  test('polynomial vectors and malformed polynomial guards', () {
    final format = CraftBitVector();
    CraftMatrixUtil.makeTypeInfoBits(CraftErrorCorrectionLevel.L, 0, format);
    expect(asNumber(format), 0x77c4);
    final version = CraftBitVector();
    CraftMatrixUtil.makeVersionInfoBits(7, version);
    expect(asNumber(version), 0x07c94);
    expect(() => CraftMatrixUtil.calculateBCHCode(1, 0), throwsArgumentError);
    expect(() => CraftMatrixUtil.findMSBSet(-1), throwsArgumentError);
  });
  test('version words recover from every three-bit error combination', () {
    for (var version = 7; version <= 40; version++) {
      final word = CraftVersion.VERSION_DECODE_INFO[version - 7];
      expect(CraftVersion.decodeVersionInformation(word)?.getVersionNumber(),
          version);
      for (var a = 0; a < 18; a++) {
        expect(
            CraftVersion.decodeVersionInformation(word ^ (1 << a))
                ?.getVersionNumber(),
            version);
        for (var b = a + 1; b < 18; b++) {
          for (var c = b + 1; c < 18; c++) {
            expect(
                CraftVersion.decodeVersionInformation(
                        word ^ (1 << a) ^ (1 << b) ^ (1 << c))
                    ?.getVersionNumber(),
                version);
          }
        }
      }
    }
    expect(CraftVersion.decodeVersionInformation(-1), isNull);
    expect(CraftVersion.decodeVersionInformation(1 << 18), isNull);
  });
  test('reservation map agrees with every module placed for all versions', () {
    for (var number = 1; number <= 40; number++) {
      final version = CraftVersion.getVersionForNumber(number);
      final side = version.getDimensionForVersion();
      final matrix = CraftByteMatrix(side, side);
      CraftMatrixUtil.clearMatrix(matrix);
      CraftMatrixUtil.embedBasicPatterns(number, matrix);
      CraftMatrixUtil.embedTypeInfo(CraftErrorCorrectionLevel.M, 3, matrix);
      CraftMatrixUtil.maybeEmbedVersionInfo(number, matrix);
      final reserved = version.buildFunctionPattern();
      var vacant = 0;
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final occupied = matrix.get(x, y) != 255;
          expect(reserved.get(x, y), occupied,
              reason: 'version $number ($x,$y)');
          if (!occupied) vacant++;
        }
      }
      expect(vacant ~/ 8, version.getTotalCodewords());
    }
  });
  test('data stripes start at bottom right and skip reserved modules', () {
    final matrix = CraftByteMatrix(21, 21);
    CraftMatrixUtil.clearMatrix(matrix);
    matrix.set(20, 20, 0);
    final data = CraftBitVector()..appendBits(0x9, 4);
    CraftMatrixUtil.embedDataBits(data, -1, matrix);
    expect(matrix.get(20, 20), 0);
    expect(matrix.get(19, 20), 1);
    expect(matrix.get(20, 19), 0);
    expect(matrix.get(19, 19), 0);
    expect(matrix.get(20, 18), 1);
  });
}
