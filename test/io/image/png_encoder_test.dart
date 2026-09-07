import 'dart:typed_data';

import 'package:dpdf/src/io/image/png_encoder.dart';
import 'package:dpdf/src/platform/compression.dart';
import 'package:test/test.dart';

/// The eight bytes every PNG starts with.
const _signature = [137, 80, 78, 71, 13, 10, 26, 10];

/// Reads the IHDR fields straight out of the encoded bytes.
({int width, int height, int bitDepth, int colourType}) _header(Uint8List png) {
  // signature (8) + length (4) + "IHDR" (4) = 16
  int be32(int at) =>
      (png[at] << 24) | (png[at + 1] << 16) | (png[at + 2] << 8) | png[at + 3];
  return (
    width: be32(16),
    height: be32(20),
    bitDepth: png[24],
    colourType: png[25],
  );
}

void main() {
  group('PngEncoder.encode', () {
    test('writes a signature and an IHDR that matches the request', () {
      final pixels = Uint8List(4 * 3 * 4); // 4x3 RGBA

      final png = PngEncoder.encode(pixels, width: 4, height: 3);

      expect(png.sublist(0, 8), equals(_signature));
      final header = _header(png);
      expect(header.width, equals(4));
      expect(header.height, equals(3));
      expect(header.bitDepth, equals(8));
      expect(header.colourType, equals(6)); // RGBA
    });

    test('maps each format to its PNG colour type', () {
      for (final entry in {
        PngPixelFormat.grayscale: 0,
        PngPixelFormat.rgb: 2,
        PngPixelFormat.grayscaleAlpha: 4,
        PngPixelFormat.rgba: 6,
      }.entries) {
        final png = PngEncoder.encode(
          Uint8List(2 * 2 * entry.key.channels),
          width: 2,
          height: 2,
          format: entry.key,
        );
        expect(_header(png).colourType, equals(entry.value),
            reason: entry.key.name);
      }
    });

    test('stores exactly the samples it was given', () {
      const width = 9, height = 7;
      final pixels = Uint8List(width * height * 3);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 3;
          pixels[i] = x * 20;
          pixels[i + 1] = y * 30;
          pixels[i + 2] = 255 - x * 10;
        }
      }

      final png = PngEncoder.encode(pixels,
          width: width, height: height, format: PngPixelFormat.rgb);

      // Inflate the IDAT and strip the per-row filter byte, which this writer
      // always sets to 0 (None).
      final raw = Uint8List.fromList(zlib.decode(_idatOf(png)));
      const stride = width * 3;
      expect(raw, hasLength((stride + 1) * height));
      for (var y = 0; y < height; y++) {
        expect(raw[y * (stride + 1)], isZero, reason: 'row $y filter');
        expect(raw.sublist(y * (stride + 1) + 1, (y + 1) * (stride + 1)),
            equals(pixels.sublist(y * stride, (y + 1) * stride)),
            reason: 'row $y');
      }
    });

    test('closes the file with IEND and writes correct CRCs', () {
      final png = PngEncoder.encode(Uint8List(2 * 2 * 4), width: 2, height: 2);

      expect(_chunkTypes(png), containsAllInOrder(['IHDR', 'IDAT', 'IEND']));
      expect(_crcsAreValid(png), isTrue);
    });

    test('rejects a buffer too small for the geometry', () {
      expect(
        () => PngEncoder.encode(Uint8List(10), width: 4, height: 4),
        throwsArgumentError,
      );
      expect(
        () => PngEncoder.encode(Uint8List(4), width: 0, height: 1),
        throwsArgumentError,
      );
    });
  });

  group('PngEncoder.encodeArgb32', () {
    test('unpacks 0xAARRGGBB into RGBA bytes', () {
      final pixels = Uint32List.fromList([0xFF804020, 0x8000FF00]);

      final png = PngEncoder.encodeArgb32(pixels, width: 2, height: 1);

      expect(_header(png).colourType, equals(6));
      expect(_header(png).width, equals(2));
    });

    test('drops alpha when the caller says the surface is opaque', () {
      final pixels = Uint32List.fromList([0xFF112233]);

      final png =
          PngEncoder.encodeArgb32(pixels, width: 1, height: 1, opaque: true);

      expect(_header(png).colourType, equals(2)); // RGB
    });

    test('divides out premultiplied alpha', () {
      // Half-transparent pure red, premultiplied: 0x80 alpha, 0x80 red.
      final premultiplied = Uint32List.fromList([0x80800000]);

      final straight = PngEncoder.encodeArgb32(premultiplied,
          width: 1, height: 1, premultiplied: true);
      final asIs = PngEncoder.encodeArgb32(premultiplied, width: 1, height: 1);

      // The two must differ: dividing 0x80 by 0x80/255 gives full red.
      expect(straight, isNot(equals(asIs)));
    });

    test('rejects a buffer too small for the geometry', () {
      expect(
        () => PngEncoder.encodeArgb32(Uint32List(3), width: 2, height: 2),
        throwsArgumentError,
      );
    });
  });
}

/// Concatenates every IDAT chunk's payload.
Uint8List _idatOf(Uint8List png) {
  final out = BytesBuilder();
  _walkChunks(png, (type, data) {
    if (type == 'IDAT') out.add(data);
  });
  return out.takeBytes();
}

List<String> _chunkTypes(Uint8List png) {
  final types = <String>[];
  _walkChunks(png, (type, _) => types.add(type));
  return types;
}

bool _crcsAreValid(Uint8List png) {
  var valid = true;
  var at = 8;
  while (at + 8 <= png.length) {
    final length = _be32(png, at);
    final end = at + 8 + length;
    if (end + 4 > png.length) break;
    final declared = _be32(png, end);
    if (_crc32(Uint8List.sublistView(png, at + 4, end)) != declared) {
      valid = false;
    }
    at = end + 4;
  }
  return valid;
}

void _walkChunks(Uint8List png, void Function(String type, Uint8List data) f) {
  var at = 8; // past the signature
  while (at + 8 <= png.length) {
    final length = _be32(png, at);
    final type = String.fromCharCodes(png, at + 4, at + 8);
    final start = at + 8;
    if (start + length > png.length) break;
    f(type, Uint8List.sublistView(png, start, start + length));
    at = start + length + 4; // skip the CRC
  }
}

int _be32(Uint8List b, int at) =>
    (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

int _crc32(Uint8List bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
