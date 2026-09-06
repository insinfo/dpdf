import 'dart:typed_data';
import 'package:pdfcraft/src/io/font/type1_font.dart';
import 'package:pdfcraft/src/io/font/otf/glyph.dart';
import 'package:pdfcraft/src/commons/utils/value_utils.dart';
import 'package:pdfcraft/src/io/source/random_access_file_or_array.dart';
import 'package:pdfcraft/src/io/source/byte_utils.dart';
import 'package:test/test.dart';

void main() {
  test('kerning pairs keep both Unicode scalars without 32-bit collisions', () {
    final font = CraftType1Font.createBuiltInFont('Helvetica');
    font.kernPairs[(0x10001, 65)] = -7;
    font.kernPairs[(0x20001, 65)] = -11;
    expect(
        font.getKerningByGlyph(
            CraftGlyph(1, 600, 0x10001), CraftGlyph(2, 600, 65)),
        -7);
    expect(
        font.getKerningByGlyph(
            CraftGlyph(3, 600, 0x20001), CraftGlyph(2, 600, 65)),
        -11);
  });
  test('double bit conversion uses exact signed BigInt bits', () {
    for (final value in [-0.0, 1e200, -123.456, double.infinity]) {
      final restored =
          ValueUtils.longBitsToDouble(ValueUtils.doubleToLongBits(value));
      expect(restored, value);
      expect(restored.isNegative, value.isNegative);
    }
  });
  test('floating point reader preserves complete IEEE bits in either order',
      () {
    for (final endian in [Endian.big, Endian.little]) {
      for (final value in [-123.456, double.infinity, -0.0, 1e200]) {
        final data = ByteData(8)..setFloat64(0, value, endian);
        final reader = CraftRandomAccessFileOrArray(data.buffer.asUint8List());
        final result =
            endian == Endian.big ? reader.readDouble() : reader.readDoubleLE();
        expect(result, value);
        expect(result.isNegative, value.isNegative);
      }
    }
  });
  test('signed 64-bit integer reader retains precision with BigInt', () {
    final positive =
        Uint8List.fromList([0x7f, 255, 255, 255, 255, 255, 255, 255]);
    expect(CraftRandomAccessFileOrArray(positive).readBigInt64(),
        (BigInt.one << 63) - BigInt.one);
    expect(
        CraftRandomAccessFileOrArray(
                Uint8List.fromList(positive.reversed.toList()))
            .readBigInt64(endian: Endian.little),
        (BigInt.one << 63) - BigInt.one);
    expect(
        CraftRandomAccessFileOrArray(
            Uint8List.fromList([128, 0, 0, 0, 0, 0, 0, 0])).readBigInt64(),
        -(BigInt.one << 63));
    expect(
        CraftRandomAccessFileOrArray(
            Uint8List.fromList([0, 0, 0, 1, 0, 0, 0, 1])).readLong(),
        4294967297);
  });
  test('large PDF number formatting does not depend on int precision', () {
    expect(String.fromCharCodes(CraftByteUtils.getIsoBytesFromDouble(1e20)),
        '9223372036854775807');
    expect(String.fromCharCodes(CraftByteUtils.getIsoBytesFromDouble(-1e20)),
        '-9223372036854775807');
  });
}
