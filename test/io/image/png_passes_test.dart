import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/platform/compression.dart';
import 'package:dpdf/src/io/image/image_data_factory.dart';

Uint8List pngFixture(int model, int depth, int width, int height,
    {bool interlace = true, bool truncate = false}) {
  final bands = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[model]!;
  final raster = <int>[];
  for (final (left, top, dx, dy) in interlace
      ? [
          (0, 0, 8, 8),
          (4, 0, 8, 8),
          (0, 4, 4, 8),
          (2, 0, 4, 4),
          (0, 2, 2, 4),
          (1, 0, 2, 2),
          (0, 1, 1, 2)
        ]
      : [(0, 0, 1, 1)]) {
    if (left >= width) continue;
    for (var y = top; y < height; y += dy) {
      raster.add(0);
      for (var x = left; x < width; x += dx) {
        for (var c = 0; c < bands; c++) {
          raster.add(model == 3 ? (x + y) % 2 : (x + y + c + 1) % 256);
          if (depth == 16) raster.add(0);
        }
      }
    }
  }
  final result = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String name, List<int> payload) {
    final data = [...name.codeUnits, ...payload];
    var crc = 0xffffffff;
    for (final byte in data) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
      }
    }
    final length = ByteData(4)..setUint32(0, payload.length);
    final checksum = ByteData(4)..setUint32(0, crc ^ 0xffffffff);
    result
      ..add(length.buffer.asUint8List())
      ..add(data)
      ..add(checksum.buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, depth)
    ..setUint8(9, model)
    ..setUint8(12, interlace ? 1 : 0);
  chunk('IHDR', header.buffer.asUint8List());
  if (model == 3) {
    chunk('PLTE', [0, 0, 0, 255, 255, 255]);
    chunk('tRNS', [128, 255]);
  }
  if (truncate) raster.removeLast();
  chunk('IDAT', zlib.encode(raster));
  chunk('IEND', []);
  return result.takeBytes();
}

void main() {
  for (final model in [0, 2, 3, 4, 6]) {
    for (final depth in model == 3 ? [8] : [8, 16]) {
      for (final side in [1, 3, 9]) {
        test('Adam7 model $model depth $depth ${side}x$side', () {
          final image =
              ImageDataFactory.create(pngFixture(model, depth, side, side));
          final colors = model == 2 || model == 6 ? 3 : 1;
          expect(image.getData(), [
            for (var y = 0; y < side; y++)
              for (var x = 0; x < side; x++)
                for (var c = 0; c < colors; c++)
                  model == 3 ? (x + y) % 2 : x + y + c + 1
          ]);
          if (model == 4 || model == 6) {
            expect(image.imageMask!.getData(), [
              for (var y = 0; y < side; y++)
                for (var x = 0; x < side; x++) x + y + colors + 1
            ]);
          }
          if (model == 3) {
            expect(image.imageMask!.getData(), [
              for (var y = 0; y < side; y++)
                for (var x = 0; x < side; x++) (x + y).isEven ? 128 : 255
            ]);
          }
        });
      }
    }
  }
  test('indexed transparency preserves compressed base image', () {
    final image =
        ImageDataFactory.create(pngFixture(3, 8, 3, 3, interlace: false));
    expect(image.isDeflated(), isTrue);
    expect(image.imageMask!.getData(),
        [128, 255, 128, 255, 128, 255, 128, 255, 128]);
  });
  test('incomplete Adam7 scanline is rejected', () {
    expect(
        () => ImageDataFactory.create(pngFixture(6, 8, 3, 3, truncate: true)),
        throwsA(isA<Exception>()));
  });
}
