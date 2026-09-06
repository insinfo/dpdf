import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pdfcraft/src/io/image/image_data_factory.dart';

Uint8List bitmap(int bits, bool topDown, int width) {
  const height = 3;
  final colors = bits <= 8 ? 1 << bits : 0;
  final start = 54 + colors * 4;
  final stride = ((width * bits + 31) ~/ 32) * 4;
  final data = ByteData(start + stride * height);
  data.setUint16(0, 0x4d42, Endian.little);
  data.setUint32(2, data.lengthInBytes, Endian.little);
  data.setUint32(10, start, Endian.little);
  data.setUint32(14, 40, Endian.little);
  data.setInt32(18, width, Endian.little);
  data.setInt32(22, topDown ? -height : height, Endian.little);
  data.setUint16(26, 1, Endian.little);
  data.setUint16(28, bits, Endian.little);
  data.setUint32(34, stride * height, Endian.little);
  for (var row = 0; row < height; row++) {
    final visual = topDown ? row : height - row - 1;
    for (var x = 0; x < width; x++) {
      final offset = start + stride * row + (x * bits ~/ 8);
      if (bits == 24 || bits == 32) {
        data.setUint8(offset, visual + 3);
        data.setUint8(offset + 1, visual + 2);
        data.setUint8(offset + 2, visual + 1);
      } else if (bits == 16) {
        data.setUint16(offset, (visual + 1) << 10, Endian.little);
      } else if (bits == 8) {
        data.setUint8(offset, visual + 1);
      } else if (bits == 4) {
        data.setUint8(offset,
            data.getUint8(offset) | ((visual + 1) << (x.isEven ? 4 : 0)));
      } else {
        data.setUint8(
            offset, data.getUint8(offset) | ((visual % 2) << (7 - x % 8)));
      }
    }
  }
  return data.buffer.asUint8List();
}

Uint8List gif(int height, bool interlaced) {
  final rows = <int>[];
  for (final (start, step)
      in interlaced ? [(0, 8), (4, 8), (2, 4), (1, 2)] : [(0, 1)]) {
    for (var y = start; y < height; y += step) {
      rows.add(y);
    }
  }
  // Clear before each literal keeps every LZW code at three bits.
  final codes = <int>[
    for (final y in rows) ...[4, y % 4],
    5
  ];
  final packed = Uint8List((codes.length * 3 + 7) ~/ 8);
  for (var i = 0; i < codes.length; i++) {
    for (var bit = 0; bit < 3; bit++) {
      final pos = i * 3 + bit;
      packed[pos ~/ 8] |= ((codes[i] >> bit) & 1) << (pos % 8);
    }
  }
  return Uint8List.fromList([
    ...'GIF89a'.codeUnits,
    1,
    0,
    height,
    0,
    0x81,
    0,
    0,
    0,
    0,
    0,
    255,
    0,
    0,
    0,
    255,
    0,
    0,
    0,
    255,
    0x2c,
    0,
    0,
    0,
    0,
    1,
    0,
    height,
    0,
    interlaced ? 0x40 : 0,
    2,
    packed.length,
    ...packed,
    0,
    0x3b,
  ]);
}

void main() {
  for (final bits in [1, 4, 8, 16, 24, 32]) {
    for (final width in [1, 3, 8]) {
      test('BMP $bits-bit width $width removes padding and flips stored rows',
          () {
        final top = CraftImageDataFactory.create(bitmap(bits, true, width));
        final bottom = CraftImageDataFactory.create(bitmap(bits, false, width));
        expect(bottom.getData(), top.getData());
        if (bits == 24 || bits == 32) {
          expect(top.getData()!.take(3), [1, 2, 3]);
          expect(top.getData()!.skip(width * 3).take(3), [2, 3, 4]);
        }
        if (bits == 16) expect(top.getData()!.take(3), [8, 0, 0]);
        if (bits == 8)
          expect(top.getData()!.take(width), List.filled(width, 1));
      });
    }
  }
  for (final height in [1, 2, 3, 4, 5, 8, 9, 17]) {
    test('GIF interlace height $height visits each row once', () {
      final interlaced = CraftImageDataFactory.create(gif(height, true));
      final plain = CraftImageDataFactory.create(gif(height, false));
      expect(interlaced.getData(), plain.getData());
      expect(interlaced.getData(),
          [for (var y = 0; y < height; y++) (y % 4) << 6]);
    });
  }
}
