import 'dart:math';
import 'dart:typed_data';

import 'package:dpdf/src/io/image/jpeg_arithmetic_decoder.dart';
import 'package:dpdf/src/io/image/jpeg_decoder.dart';
import 'package:test/test.dart';

import 'jpeg_arithmetic_support.dart';

/// The prediction of T.81 Table H.1 for the sample at ([x], [y]) of [plane],
/// with the line and restart rules of H.1.2.1.
int _predict(List<List<int>> plane, int x, int y, int predictor, int firstRow,
    int initial) {
  if (predictor == 0) return 0;
  if (y == firstRow) return x == 0 ? initial : plane[y][x - 1];
  if (x == 0) return plane[y - 1][0];
  final ra = plane[y][x - 1];
  final rb = plane[y - 1][x];
  final rc = plane[y - 1][x - 1];
  return switch (predictor) {
    1 => ra,
    2 => rb,
    3 => rc,
    4 => ra + rb - rc,
    5 => ra + ((rb - rc) >> 1),
    6 => rb + ((ra - rc) >> 1),
    _ => (ra + rb) >> 1,
  };
}

/// The prediction error, taken modulo 2^16 and read back as a signed 16-bit
/// integer, H.1.2.1.
int _difference(int sample, int prediction) {
  final value = (sample - prediction) & 0xFFFF;
  return value >= 0x8000 ? value - 0x10000 : value;
}

/// Builds a single-component lossless JPEG over [source], which holds samples
/// of [precision] bits.
Uint8List buildLossless(
  List<List<int>> source, {
  required int predictor,
  required int precision,
  int pointTransform = 0,
  bool arithmeticCoding = false,
  int restartInterval = 0,
}) {
  final height = source.length;
  final width = source.first.length;
  final initial = 1 << (precision - pointTransform - 1);

  // The decoder works on point-transformed samples, A.4.
  final plane = [
    for (final row in source)
      [for (final value in row) value >> pointTransform],
  ];

  final rowsPerInterval = restartInterval == 0 ? height : restartInterval;
  final segments = <Uint8List>[];
  for (var start = 0; start < height; start += rowsPerInterval) {
    final stop = min(start + rowsPerInterval, height);
    if (arithmeticCoding) {
      final encoder = ArithmeticEncoder();
      final model = ArithmeticModelEncoder(encoder, JpegArithConditioning())
        ..resetDcStats(0);
      // The conditioning categories of the differences already coded.
      final categories = [
        for (var y = 0; y < height; y++) List<int>.filled(width, 0),
      ];
      for (var y = start; y < stop; y++) {
        for (var x = 0; x < width; x++) {
          final prediction = _predict(plane, x, y, predictor, start, initial);
          final left = x == 0 ? 0 : categories[y][x - 1];
          final above = y == start ? 0 : categories[y - 1][x];
          categories[y][x] = model.encodeLosslessDifference(
              0, left, above, _difference(plane[y][x], prediction));
        }
      }
      segments.add(encoder.finish());
    } else {
      final writer = HuffmanBitWriter();
      for (var y = start; y < stop; y++) {
        for (var x = 0; x < width; x++) {
          final prediction = _predict(plane, x, y, predictor, start, initial);
          final difference = _difference(plane[y][x], prediction);
          if (difference == -32768) {
            // Table H.2: category 16 carries no appended bits.
            writer.writeBits(16, FlatDcTable.codeLength);
            continue;
          }
          final magnitude = difference.abs();
          var category = 0;
          while (magnitude >= (1 << category)) {
            category++;
          }
          writer.writeBits(category, FlatDcTable.codeLength);
          if (category != 0) {
            final bits =
                difference < 0 ? difference + (1 << category) - 1 : difference;
            writer.writeBits(bits, category);
          }
        }
      }
      segments.add(writer.finish());
    }
  }

  final builder = JpegBuilder()..soi();
  if (!arithmeticCoding) {
    builder.dht(0, 0, FlatDcTable.counts, FlatDcTable.values);
  }
  if (restartInterval != 0) builder.dri(restartInterval * width);
  builder
    ..sof(arithmeticCoding ? 0xCB : 0xC3, precision, height, width,
        const [FrameComponent(1, 1, 1)])
    ..sos(const [ScanComponent(1)], segments.first,
        ss: predictor, se: 0, ah: 0, al: pointTransform);
  for (var i = 1; i < segments.length; i++) {
    builder
      ..restart(i - 1)
      ..bytes.addAll(segments[i]);
  }
  builder.eoi();
  return builder.build();
}

/// The eight-bit plane the decoder should produce from [source].
List<int> expectedPlane(List<List<int>> source,
    {required int precision, int pointTransform = 0}) {
  final shift = precision - 8;
  return [
    for (final row in source)
      for (final value in row)
        (() {
          var reconstructed = (value >> pointTransform) << pointTransform;
          reconstructed =
              shift > 0 ? reconstructed >> shift : reconstructed << -shift;
          return reconstructed.clamp(0, 255);
        })(),
  ];
}

void main() {
  group('lossless JPEG with Huffman coding, T.81 SOF3', () {
    late List<List<int>> source;

    setUp(() {
      final random = Random(20240913);
      source = [
        for (var y = 0; y < 9; y++)
          [
            for (var x = 0; x < 11; x++)
              // A smooth ramp with noise, which is what prediction is for.
              (20 + x * 9 + y * 7 + random.nextInt(9)).clamp(0, 255),
          ],
      ];
    });

    test('probe accepts a lossless frame', () {
      final bytes = buildLossless(source, predictor: 1, precision: 8);
      final info = JpegDecoder.probe(bytes);
      expect(info.decodable, isTrue);
      expect(info.width, equals(11));
      expect(info.height, equals(9));
      expect(info.components, equals(1));
    });

    for (var predictor = 1; predictor <= 7; predictor++) {
      test('reproduces the samples exactly with predictor $predictor', () {
        final bytes = buildLossless(source, predictor: predictor, precision: 8);
        final image = JpegDecoder.decode(bytes);
        expect(image.format, equals(JpegPixelFormat.grayscale));
        expect(image.pixels, equals(expectedPlane(source, precision: 8)));
      });
    }

    test('handles the extremes of the eight-bit range', () {
      final extremes = [
        [0, 255, 0, 255],
        [255, 0, 255, 0],
        [0, 0, 255, 255],
        [128, 128, 1, 254],
      ];
      for (var predictor = 1; predictor <= 7; predictor++) {
        final bytes =
            buildLossless(extremes, predictor: predictor, precision: 8);
        expect(JpegDecoder.decode(bytes).pixels,
            equals(expectedPlane(extremes, precision: 8)),
            reason: 'predictor $predictor');
      }
    });

    test('reads twelve-bit samples', () {
      final random = Random(5);
      final wide = [
        for (var y = 0; y < 6; y++)
          [for (var x = 0; x < 6; x++) random.nextInt(4096)],
      ];
      final bytes = buildLossless(wide, predictor: 4, precision: 12);
      expect(JpegDecoder.decode(bytes).pixels,
          equals(expectedPlane(wide, precision: 12)));
    });

    test('reads sixteen-bit samples, the widest Annex H allows', () {
      final random = Random(6);
      final wide = [
        for (var y = 0; y < 6; y++)
          [for (var x = 0; x < 6; x++) random.nextInt(65536)],
      ];
      final bytes = buildLossless(wide, predictor: 7, precision: 16);
      expect(JpegDecoder.decode(bytes).pixels,
          equals(expectedPlane(wide, precision: 16)));
    });

    test('reads two-bit samples, the narrowest Annex H allows', () {
      final narrow = [
        [0, 1, 2, 3],
        [3, 2, 1, 0],
        [1, 1, 2, 2],
      ];
      final bytes = buildLossless(narrow, predictor: 1, precision: 2);
      expect(JpegDecoder.decode(bytes).pixels,
          equals(expectedPlane(narrow, precision: 2)));
    });

    test('applies the point transform of A.4', () {
      final random = Random(77);
      final wide = [
        for (var y = 0; y < 5; y++)
          [for (var x = 0; x < 7; x++) random.nextInt(65536)],
      ];
      final bytes =
          buildLossless(wide, predictor: 2, precision: 16, pointTransform: 4);
      expect(JpegDecoder.decode(bytes).pixels,
          equals(expectedPlane(wide, precision: 16, pointTransform: 4)));
    });

    test('resynchronises at restart intervals', () {
      final bytes =
          buildLossless(source, predictor: 6, precision: 8, restartInterval: 2);
      expect(JpegDecoder.decode(bytes).pixels,
          equals(expectedPlane(source, precision: 8)));
    });

    test('rejects a predictor the standard does not define', () {
      final bytes = buildLossless(source, predictor: 1, precision: 8);
      // Rewrite Ss in the scan header to 9.
      final at = _scanHeaderStart(bytes);
      bytes[at] = 9;
      expect(
          () => JpegDecoder.decode(bytes), throwsA(isA<JpegDecodeException>()));
    });

    test('rejects predictor 0 outside a differential frame', () {
      final bytes = buildLossless(source, predictor: 1, precision: 8);
      final at = _scanHeaderStart(bytes);
      bytes[at] = 0;
      expect(
          () => JpegDecoder.decode(bytes),
          throwsA(isA<JpegDecodeException>()
              .having((e) => e.message, 'message', contains('differential'))));
    });
  });

  group('lossless JPEG with arithmetic coding, T.81 SOF11', () {
    late List<List<int>> source;

    setUp(() {
      final random = Random(4711);
      source = [
        for (var y = 0; y < 10; y++)
          [
            for (var x = 0; x < 13; x++)
              (30 + x * 6 + y * 5 + random.nextInt(11)).clamp(0, 255),
          ],
      ];
    });

    for (var predictor = 1; predictor <= 7; predictor++) {
      test('reproduces the samples exactly with predictor $predictor', () {
        final bytes = buildLossless(source,
            predictor: predictor, precision: 8, arithmeticCoding: true);
        expect(JpegDecoder.decode(bytes).pixels,
            equals(expectedPlane(source, precision: 8)));
      });
    }

    test('reads sixteen-bit samples', () {
      final random = Random(8);
      final wide = [
        for (var y = 0; y < 8; y++)
          [for (var x = 0; x < 8; x++) random.nextInt(65536)],
      ];
      final bytes = buildLossless(wide,
          predictor: 4, precision: 16, arithmeticCoding: true);
      expect(JpegDecoder.decode(bytes).pixels,
          equals(expectedPlane(wide, precision: 16)));
    });

    test('resynchronises at restart intervals', () {
      final bytes = buildLossless(source,
          predictor: 5,
          precision: 8,
          arithmeticCoding: true,
          restartInterval: 3);
      expect(JpegDecoder.decode(bytes).pixels,
          equals(expectedPlane(source, precision: 8)));
    });

    test('drives every conditioning state of the 5 by 5 array', () {
      // Alternating large and small differences of both signs, so
      // L_Context(Da, Db) visits all 25 cells of Figure H.2.
      final random = Random(2024);
      final rough = [
        for (var y = 0; y < 12; y++)
          [
            for (var x = 0; x < 12; x++)
              (x + y).isEven ? random.nextInt(16) : 240 + random.nextInt(16),
          ],
      ];
      final bytes = buildLossless(rough,
          predictor: 1, precision: 8, arithmeticCoding: true);
      expect(JpegDecoder.decode(bytes).pixels,
          equals(expectedPlane(rough, precision: 8)));
    });
  });

  group('interleaved lossless JPEG', () {
    test('walks the MCU of A.2.3 across four components', () {
      // Four components at different sampling factors, so one MCU carries
      // 4 + 2 + 2 + 1 samples. Four components make the decoder emit CMYK,
      // whose channels are the planes unchanged, so the check is exact.
      const width = 8;
      const height = 8;
      const factors = [
        [2, 2],
        [2, 1],
        [1, 2],
        [1, 1]
      ];
      const maxH = 2;
      const maxV = 2;
      final random = Random(606);
      final planes = [
        for (final factor in factors)
          [
            for (var y = 0; y < height * factor[1] ~/ maxV; y++)
              [
                for (var x = 0; x < width * factor[0] ~/ maxH; x++)
                  random.nextInt(256),
              ],
          ],
      ];

      final writer = HuffmanBitWriter();
      void codeDifference(int difference) {
        final magnitude = difference.abs();
        var category = 0;
        while (magnitude >= (1 << category)) {
          category++;
        }
        writer.writeBits(category, FlatDcTable.codeLength);
        if (category != 0) {
          writer.writeBits(
              difference < 0 ? difference + (1 << category) - 1 : difference,
              category);
        }
      }

      const mcusPerLine = width ~/ maxH;
      const mcusPerColumn = height ~/ maxV;
      for (var mcuRow = 0; mcuRow < mcusPerColumn; mcuRow++) {
        for (var mcuColumn = 0; mcuColumn < mcusPerLine; mcuColumn++) {
          for (var ci = 0; ci < factors.length; ci++) {
            final plane = planes[ci];
            for (var v = 0; v < factors[ci][1]; v++) {
              for (var h = 0; h < factors[ci][0]; h++) {
                final y = mcuRow * factors[ci][1] + v;
                final x = mcuColumn * factors[ci][0] + h;
                final prediction = _predict(plane, x, y, 1, 0, 128);
                codeDifference(_difference(plane[y][x], prediction));
              }
            }
          }
        }
      }

      final bytes = (JpegBuilder()
            ..soi()
            ..dht(0, 0, FlatDcTable.counts, FlatDcTable.values)
            ..sof(0xC3, 8, height, width, [
              for (var i = 0; i < factors.length; i++)
                FrameComponent(i + 1, factors[i][0], factors[i][1]),
            ])
            ..sos([
              for (var i = 0; i < factors.length; i++) ScanComponent(i + 1),
            ], writer.finish(), ss: 1, se: 0)
            ..eoi())
          .build();

      final image = JpegDecoder.decode(bytes);
      expect(image.format, equals(JpegPixelFormat.cmyk));
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          for (var ci = 0; ci < factors.length; ci++) {
            final scaleX = maxH ~/ factors[ci][0];
            final scaleY = maxV ~/ factors[ci][1];
            expect(image.pixels[(y * width + x) * 4 + ci],
                equals(planes[ci][y ~/ scaleY][x ~/ scaleX]),
                reason: 'component $ci at ($x, $y)');
          }
        }
      }
    });
  });
}

/// Offset of the Ss byte in the first SOS header of [bytes].
int _scanHeaderStart(Uint8List bytes) {
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] != 0xFF || bytes[i + 1] != 0xDA) continue;
    final length = (bytes[i + 2] << 8) | bytes[i + 3];
    return i + 2 + length - 3;
  }
  return -1;
}
