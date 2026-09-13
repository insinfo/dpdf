import 'dart:math';
import 'dart:typed_data';

import 'package:dpdf/src/io/image/jpeg_arithmetic_decoder.dart';
import 'package:dpdf/src/io/image/jpeg_decoder.dart';
import 'package:test/test.dart';

import 'jpeg_arithmetic_support.dart';

/// A flat quantisation table, so a coefficient is its own dequantised value.
final Int32List _unitQuant = Int32List(64)..fillRange(0, 64, 1);

/// The samples a block of [coefficients] should decode to: the reference IDCT
/// of T.81 A.3.3 plus the level shift and range limiting of A.3.1.
List<int> _expectedBlock(Int32List coefficients, Int32List quant) {
  final samples = referenceIdct(coefficients, quant);
  return [
    for (final value in samples) (value.round() + 128).clamp(0, 255),
  ];
}

/// Blocks of a single-component image, laid out in raster order.
Int32List _blockAt(List<Int32List> blocks, int index) => blocks[index];

void main() {
  group('sequential arithmetic JPEG, T.81 SOF9', () {
    /// Builds a grayscale SOF9 file whose blocks hold [blocks] verbatim, and
    /// returns it together with the samples it should decode to.
    (Uint8List, List<int>) buildGrayscale(
      List<Int32List> blocks,
      int blocksPerLine,
      int blocksPerColumn, {
      int restartInterval = 0,
      List<List<int>> dacEntries = const [],
      JpegArithConditioning? conditioning,
    }) {
      final conditions = conditioning ?? JpegArithConditioning();
      final encoder = ArithmeticEncoder();
      final model = ArithmeticModelEncoder(encoder, conditions);

      final total = blocksPerLine * blocksPerColumn;
      final interval = restartInterval == 0 ? total : restartInterval;
      final segments = <Uint8List>[];
      var block = 0;
      var current = encoder;
      var currentModel = model;
      while (block < total) {
        currentModel
          ..resetDcStats(0)
          ..resetAcStats(0)
          ..resetPredictions();
        final stop = min(block + interval, total);
        var previousDc = 0;
        for (; block < stop; block++) {
          final data = _blockAt(blocks, block);
          currentModel.encodeDcDifference(0, 0, data[0] - previousDc);
          previousDc = data[0];
          currentModel.encodeAcCoefficients(0, data, 0, 1, 63, 0);
        }
        segments.add(current.finish());
        if (block < total) {
          current = ArithmeticEncoder();
          currentModel = ArithmeticModelEncoder(current, conditions);
        }
      }

      final builder = JpegBuilder()
        ..soi()
        ..dqt(0, _unitQuant);
      if (dacEntries.isNotEmpty) builder.dac(dacEntries);
      if (restartInterval != 0) builder.dri(restartInterval);
      builder
        ..sof(0xC9, 8, blocksPerColumn * 8, blocksPerLine * 8,
            const [FrameComponent(1, 1, 1)])
        ..sos(const [ScanComponent(1)], segments.first);
      for (var i = 1; i < segments.length; i++) {
        builder
          ..restart(i - 1)
          ..bytes.addAll(segments[i]);
      }
      builder.eoi();

      final width = blocksPerLine * 8;
      final expected = List<int>.filled(width * blocksPerColumn * 8, 0);
      for (var b = 0; b < total; b++) {
        final samples = _expectedBlock(blocks[b], _unitQuant);
        final originX = (b % blocksPerLine) * 8;
        final originY = (b ~/ blocksPerLine) * 8;
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 8; x++) {
            expected[(originY + y) * width + originX + x] = samples[y * 8 + x];
          }
        }
      }
      return (builder.build(), expected);
    }

    void expectClose(Uint8List actual, List<int> expected) {
      expect(actual.length, equals(expected.length));
      var worst = 0;
      for (var i = 0; i < expected.length; i++) {
        final delta = (actual[i] - expected[i]).abs();
        if (delta > worst) worst = delta;
      }
      expect(worst, lessThanOrEqualTo(1),
          reason: 'the fast IDCT must track the reference within one count');
    }

    test('probe reports an arithmetic file as decodable', () {
      final blocks = [Int32List(64)..[0] = 0];
      final (bytes, _) = buildGrayscale(blocks, 1, 1);
      final info = JpegDecoder.probe(bytes);
      expect(info.decodable, isTrue);
      expect(info.width, equals(8));
      expect(info.height, equals(8));
      expect(info.components, equals(1));
    });

    test('decodes a DC-only block', () {
      final blocks = [Int32List(64)..[0] = 64];
      final (bytes, expected) = buildGrayscale(blocks, 1, 1);
      final image = JpegDecoder.decode(bytes);
      expect(image.format, equals(JpegPixelFormat.grayscale));
      expectClose(image.pixels, expected);
      // A DC of 64 with a unit quantiser is a flat 8 above mid grey.
      expect(image.pixels.every((p) => p == 136), isTrue);
    });

    test('decodes DC differences that walk both conditioning categories', () {
      // Zero, small and large differences of both signs, so every branch of
      // DC_Context(Da) in F.1.4.4.1.2 is taken.
      const dcs = [0, 1, 1, -1, 40, -400, -400, 4000];
      final blocks = [
        for (final dc in dcs) Int32List(64)..[0] = dc,
      ];
      final (bytes, expected) = buildGrayscale(blocks, 4, 2);
      expectClose(JpegDecoder.decode(bytes).pixels, expected);
    });

    test('decodes AC coefficients across the whole band', () {
      final random = Random(4242);
      final blocks = <Int32List>[];
      for (var b = 0; b < 8; b++) {
        final block = Int32List(64);
        block[0] = random.nextInt(200) - 100;
        for (var k = 1; k < 64; k++) {
          // A sparse band, the way a real quantised block looks.
          if (random.nextInt(3) == 0) {
            block[zigZag[k]] = random.nextInt(41) - 20;
          }
        }
        blocks.add(block);
      }
      final (bytes, expected) = buildGrayscale(blocks, 4, 2);
      expectClose(JpegDecoder.decode(bytes).pixels, expected);
    });

    test('decodes a coefficient at every magnitude category', () {
      // One block per category so the X1..X15 and M2..M15 bins all get used.
      final blocks = <Int32List>[];
      for (var bit = 0; bit < 12; bit++) {
        final block = Int32List(64);
        block[0] = 1 << bit;
        block[zigZag[1]] = (1 << bit) - 1;
        block[zigZag[40]] = -(1 << bit);
        blocks.add(block);
      }
      final (bytes, expected) = buildGrayscale(blocks, 4, 3);
      expectClose(JpegDecoder.decode(bytes).pixels, expected);
    });

    test('resynchronises at restart intervals', () {
      final random = Random(11);
      final blocks = [
        for (var b = 0; b < 12; b++)
          Int32List(64)
            ..[0] = random.nextInt(400) - 200
            ..[zigZag[3]] = random.nextInt(60) - 30,
      ];
      final (bytes, expected) =
          buildGrayscale(blocks, 4, 3, restartInterval: 2);
      expectClose(JpegDecoder.decode(bytes).pixels, expected);
    });

    test('honours the conditioning bounds a DAC segment sets', () {
      final conditioning = JpegArithConditioning()
        ..apply(0, 0, 0x42) // U = 4, L = 2
        ..apply(1, 0, 20); // Kx = 20
      final random = Random(5);
      final blocks = [
        for (var b = 0; b < 8; b++)
          Int32List(64)
            ..[0] = random.nextInt(600) - 300
            ..[zigZag[7]] = random.nextInt(80) - 40
            ..[zigZag[30]] = random.nextInt(80) - 40,
      ];
      final (bytes, expected) = buildGrayscale(
        blocks,
        4,
        2,
        dacEntries: const [
          [0, 0, 0x42],
          [1, 0, 20],
        ],
        conditioning: conditioning,
      );
      expectClose(JpegDecoder.decode(bytes).pixels, expected);

      // The same stream read with the default bounds must not agree: the
      // conditioning really is in play.
      final withoutDac = Uint8List.fromList(bytes);
      // Blank the DAC segment's marker into a comment so it is skipped.
      final at = _findMarker(withoutDac, 0xCC);
      expect(at, greaterThan(0));
      withoutDac[at + 1] = 0xFE; // COM
      final wrong = JpegDecoder.decode(withoutDac).pixels;
      var differences = 0;
      for (var i = 0; i < wrong.length; i++) {
        if ((wrong[i] - expected[i]).abs() > 1) differences++;
      }
      expect(differences, greaterThan(0));
    });
  });

  group('three-component arithmetic JPEG', () {
    test('decodes an interleaved 4:2:0 frame', () {
      // Y at 2x2, Cb and Cr at 1x1: one MCU covers 16x16 pixels.
      final encoder = ArithmeticEncoder();
      final conditioning = JpegArithConditioning();
      final model = ArithmeticModelEncoder(encoder, conditioning)
        ..resetDcStats(0)
        ..resetDcStats(1)
        ..resetAcStats(0)
        ..resetAcStats(1)
        ..resetPredictions();

      // Four luma blocks then one Cb and one Cr block, T.81 A.2.3.
      final luma = [
        for (var i = 0; i < 4; i++) Int32List(64)..[0] = 100 + 40 * i,
      ];
      final cb = Int32List(64)..[0] = -160;
      final cr = Int32List(64)..[0] = 80;

      var lumaPrediction = 0;
      for (final block in luma) {
        model.encodeDcDifference(0, 0, block[0] - lumaPrediction);
        lumaPrediction = block[0];
        model.encodeAcCoefficients(0, block, 0, 1, 63, 0);
      }
      model.encodeDcDifference(1, 1, cb[0]);
      model.encodeAcCoefficients(1, cb, 0, 1, 63, 0);
      model.encodeDcDifference(2, 1, cr[0]);
      model.encodeAcCoefficients(1, cr, 0, 1, 63, 0);

      final bytes = (JpegBuilder()
            ..soi()
            ..dqt(0, _unitQuant)
            ..dqt(1, _unitQuant)
            ..sof(0xC9, 8, 16, 16, const [
              FrameComponent(1, 2, 2),
              FrameComponent(2, 1, 1, 1),
              FrameComponent(3, 1, 1, 1),
            ])
            ..sos(const [
              ScanComponent(1),
              ScanComponent(2, 1, 1),
              ScanComponent(3, 1, 1),
            ], encoder.finish())
            ..eoi())
          .build();

      final image = JpegDecoder.decode(bytes);
      expect(image.format, equals(JpegPixelFormat.rgb));
      expect(image.width, equals(16));
      expect(image.height, equals(16));

      // Each luma block is flat, so the whole 8x8 quadrant shares one colour.
      int at(int x, int y, int channel) =>
          image.pixels[(y * 16 + x) * 3 + channel];
      for (var quadrant = 0; quadrant < 4; quadrant++) {
        final originX = (quadrant % 2) * 8;
        final originY = (quadrant ~/ 2) * 8;
        final r = at(originX, originY, 0);
        final g = at(originX, originY, 1);
        final b = at(originX, originY, 2);
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 8; x++) {
            expect(at(originX + x, originY + y, 0), equals(r));
            expect(at(originX + x, originY + y, 1), equals(g));
            expect(at(originX + x, originY + y, 2), equals(b));
          }
        }
      }
      // Cb is strongly negative and Cr positive, so the frame reads red.
      expect(at(0, 0, 0), greaterThan(at(0, 0, 2)));
      // The four luma blocks brighten left to right, top to bottom.
      expect(at(8, 8, 0), greaterThan(at(0, 0, 0)));
    });
  });

  group('wider precision', () {
    test('decodes a twelve-bit DCT frame, scaling the output to eight bits',
        () {
      // T.81 F.1.6: the arithmetic coding of a 12-bit frame is identical to
      // the 8-bit one, so only the level shift and range limit change.
      final block = Int32List(64)..[0] = 1024;
      final encoder = ArithmeticEncoder();
      final model = ArithmeticModelEncoder(encoder, JpegArithConditioning())
        ..resetDcStats(0)
        ..resetAcStats(0)
        ..resetPredictions()
        ..encodeDcDifference(0, 0, block[0]);
      model.encodeAcCoefficients(0, block, 0, 1, 63, 0);

      final bytes = (JpegBuilder()
            ..soi()
            ..dqt(0, _unitQuant)
            ..sof(0xC9, 12, 8, 8, const [FrameComponent(1, 1, 1)])
            ..sos(const [ScanComponent(1)], encoder.finish())
            ..eoi())
          .build();

      expect(JpegDecoder.probe(bytes).decodable, isTrue);
      final image = JpegDecoder.decode(bytes);
      // A DC of 1024 with a unit quantiser is 128 above the 12-bit midpoint of
      // 2048, so 2176 of 4095, which is 136 once scaled to eight bits.
      expect(image.pixels.every((p) => p == 136), isTrue,
          reason: 'got ${image.pixels.take(4).toList()}');
    });

    test('reads sixteen-bit quantisation values, T.81 B.2.4.1', () {
      // Pq = 1 makes every Qk a two-byte value; 300 does not fit in one.
      final quant = Int32List(64)..fillRange(0, 64, 1);
      quant[0] = 300;
      final block = Int32List(64)..[0] = 2;
      final encoder = ArithmeticEncoder();
      final model = ArithmeticModelEncoder(encoder, JpegArithConditioning())
        ..resetDcStats(0)
        ..resetAcStats(0)
        ..resetPredictions()
        ..encodeDcDifference(0, 0, block[0]);
      model.encodeAcCoefficients(0, block, 0, 1, 63, 0);

      final payload = <int>[0x10];
      for (var i = 0; i < 64; i++) {
        final value = quant[zigZag[i]];
        payload.addAll([value >> 8, value & 0xFF]);
      }
      final builder = JpegBuilder()..soi();
      builder.segment(0xDB, payload);
      builder
        ..sof(0xC9, 8, 8, 8, const [FrameComponent(1, 1, 1)])
        ..sos(const [ScanComponent(1)], encoder.finish())
        ..eoi();

      final image = JpegDecoder.decode(builder.build());
      // DC 2 at a quantiser of 300 is 600, a flat 75 above mid grey.
      expect(image.pixels.every((p) => p == 203), isTrue,
          reason: 'got ${image.pixels.take(4).toList()}');
    });
  });
}

/// Index of the `0xFF` of the first [code] marker in [bytes].
int _findMarker(Uint8List bytes, int code) {
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0xFF && bytes[i + 1] == code) return i;
  }
  return -1;
}
