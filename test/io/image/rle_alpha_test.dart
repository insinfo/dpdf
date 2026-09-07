import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/platform/compression.dart';
import 'package:dpdf/src/io/image/image_data_factory.dart';
import 'raster_order_test.dart' show bitmap;

Uint8List rle(int depth, List<int> commands) {
  final original = bitmap(depth, false, 3);
  final offset = ByteData.sublistView(original).getUint32(10, Endian.little);
  final data = Uint8List(offset + commands.length)
    ..setRange(0, offset, original)
    ..setRange(offset, offset + commands.length, commands);
  final view = ByteData.sublistView(data)
    ..setUint32(2, data.length, Endian.little)
    ..setUint32(30, depth == 8 ? 1 : 2, Endian.little)
    ..setUint32(34, commands.length, Endian.little);
  return view.buffer.asUint8List();
}

void main() {
  test('BMP RLE8 encoded, literal, delta and skipped cells', () {
    final image = ImageDataFactory.create(
        rle(8, [3, 1, 0, 0, 0, 3, 2, 3, 4, 0, 0, 0, 0, 2, 1, 0, 2, 5, 0, 1]));
    expect(image.getData(), [0, 5, 5, 2, 3, 4, 1, 1, 1]);
  });
  test('BMP RLE4 alternating nibbles and absolute packed samples', () {
    final image = ImageDataFactory.create(
        rle(4, [3, 0x12, 0, 0, 0, 3, 0x34, 0x50, 0, 0, 3, 0x67, 0, 1]));
    expect(image.getData(), [0x67, 0x60, 0x34, 0x50, 0x12, 0x10]);
  });
  test('BMP RLE rejects run crossing row and truncated literal', () {
    for (final commands in [
      [4, 1],
      [0, 3, 1]
    ]) {
      expect(() => ImageDataFactory.create(rle(8, commands)),
          throwsA(isA<Exception>()));
    }
  });
  test('TIFF horizontal predictor accumulates each channel and resets rows',
      () {
    final image = ImageDataFactory.create(base64.decode(
        'SUkqAB4AAAB4nOMSkZMT4ZIT4UoJsIEwABNyAh0ACwAAAQMAAQAAAAMAAAABAQMAAQAAAAIAAAACAQMAAwAAAKgAAAADAQMAAQAAAAgAAAAGAQMAAQAAAAIAAAARAQQAAQAAAAgAAAAVAQMAAQAAAAMAAAAWAQMAAQAAAAIAAAAXAQQAAQAAABUAAAAcAQMAAQAAAAEAAAA9AQMAAQAAAAIAAAAAAAAACAAIAAgA'));
    expect(zlib.decode(image.getData()!), [
      for (var x = 0; x < 6; x++) ...[10 + x * 30, 20 + x * 20, 30 + x * 10]
    ]);
  });
  test('TIFF RGBA separates color and opacity without changing samples', () {
    final image = ImageDataFactory.create(base64.decode(
        'SUkqAAgAAAALAAABBAABAAAAAgAAAAEBBAABAAAAAgAAAAIBAwAEAAAAkgAAAAMBAwABAAAAAQAAAAYBAwABAAAAAgAAABEBBAABAAAAmgAAABUBAwABAAAABAAAABYBBAABAAAAAgAAABcBBAABAAAAEAAAABwBAwABAAAAAQAAAFIBAwABAAAAAgAAAAAAAAAIAAgACAAIAAECAwQFBgcICQoLDA0ODxA='));
    expect(zlib.decode(image.getData()!),
        [1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15]);
    expect(zlib.decode(image.imageMask!.getData()!), [4, 8, 12, 16]);
  });
}
