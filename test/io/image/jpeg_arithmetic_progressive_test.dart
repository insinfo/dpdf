import 'dart:math';
import 'dart:typed_data';

import 'package:dpdf/src/io/image/jpeg_arithmetic_decoder.dart';
import 'package:dpdf/src/io/image/jpeg_decoder.dart';
import 'package:test/test.dart';

import 'jpeg_arithmetic_support.dart';

final Int32List _unitQuant = Int32List(64)..fillRange(0, 64, 1);

/// Encodes one scan over [blocks] and returns its entropy-coded segment.
Uint8List _scan(
  List<Int32List> blocks,
  void Function(ArithmeticModelEncoder model, Int32List block, int index) body,
) {
  final encoder = ArithmeticEncoder();
  final model = ArithmeticModelEncoder(encoder, JpegArithConditioning())
    ..resetDcStats(0)
    ..resetAcStats(0)
    ..resetPredictions();
  for (var i = 0; i < blocks.length; i++) {
    body(model, blocks[i], i);
  }
  return encoder.finish();
}

/// A coefficient at the precision a scan with successive approximation [al]
/// carries: division by 2^Al truncated towards zero, T.81 A.4.
int _pointTransform(int value, int al) =>
    value >= 0 ? value >> al : -((-value) >> al);

void main() {
  group('progressive arithmetic JPEG, T.81 SOF10', () {
    late List<Int32List> blocks;

    setUp(() {
      final random = Random(31337);
      blocks = [
        for (var b = 0; b < 8; b++)
          () {
            final block = Int32List(64);
            block[0] = random.nextInt(500) - 250;
            for (var k = 1; k < 64; k++) {
              if (random.nextInt(4) == 0) {
                block[zigZag[k]] = random.nextInt(61) - 30;
              }
            }
            return block;
          }(),
      ];
    });

    /// Expected samples, block by block, from the reference IDCT.
    List<int> expectedSamples(int blocksPerLine, int blocksPerColumn) {
      final width = blocksPerLine * 8;
      final out = List<int>.filled(width * blocksPerColumn * 8, 0);
      for (var b = 0; b < blocks.length; b++) {
        final samples = referenceIdct(blocks[b], _unitQuant);
        final originX = (b % blocksPerLine) * 8;
        final originY = (b ~/ blocksPerLine) * 8;
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 8; x++) {
            out[(originY + y) * width + originX + x] =
                (samples[y * 8 + x].round() + 128).clamp(0, 255);
          }
        }
      }
      return out;
    }

    test('reads spectral selection and successive approximation scans', () {
      // Four scans: DC at Al = 1, the DC correction bit, AC at Al = 1, and the
      // AC refinement, which is the full G.1.3 repertoire.
      final dcFirst = _scan(blocks, (model, block, index) {
        model.encodeDcDifference(0, 0,
            (block[0] >> 1) - (index == 0 ? 0 : blocks[index - 1][0] >> 1));
      });
      final dcRefine = _scan(blocks, (model, block, _) {
        model.encodeCorrectionBit(block[0] & 1);
      });
      final acFirst = _scan(blocks, (model, block, _) {
        model.encodeAcCoefficients(0, block, 0, 1, 63, 1);
      });
      final previous = [
        for (final block in blocks)
          Int32List.fromList([
            for (var i = 0; i < 64; i++) _pointTransform(block[i], 1) << 1,
          ]),
      ];
      final acRefine = _scan(blocks, (model, block, index) {
        model.refineAcCoefficients(0, previous[index], block, 0, 1, 63, 0);
      });

      final bytes = (JpegBuilder()
            ..soi()
            ..dqt(0, _unitQuant)
            ..sof(0xCA, 8, 16, 32, const [FrameComponent(1, 1, 1)])
            ..sos(const [ScanComponent(1)], dcFirst, ss: 0, se: 0, al: 1)
            ..sos(const [ScanComponent(1)], dcRefine, ss: 0, se: 0, ah: 1)
            ..sos(const [ScanComponent(1)], acFirst, ss: 1, se: 63, al: 1)
            ..sos(const [ScanComponent(1)], acRefine, ss: 1, se: 63, ah: 1)
            ..eoi())
          .build();

      final info = JpegDecoder.probe(bytes);
      expect(info.decodable, isTrue);
      expect(info.width, equals(32));

      final image = JpegDecoder.decode(bytes);
      final expected = expectedSamples(4, 2);
      var worst = 0;
      for (var i = 0; i < expected.length; i++) {
        final delta = (image.pixels[i] - expected[i]).abs();
        if (delta > worst) worst = delta;
      }
      expect(worst, lessThanOrEqualTo(1));
    });

    test('a DC-only progression already reconstructs the block averages', () {
      final dcOnly = _scan(blocks, (model, block, index) {
        model.encodeDcDifference(
            0, 0, block[0] - (index == 0 ? 0 : blocks[index - 1][0]));
      });
      final bytes = (JpegBuilder()
            ..soi()
            ..dqt(0, _unitQuant)
            ..sof(0xCA, 8, 16, 32, const [FrameComponent(1, 1, 1)])
            ..sos(const [ScanComponent(1)], dcOnly, ss: 0, se: 0)
            ..eoi())
          .build();

      final image = JpegDecoder.decode(bytes);
      for (var b = 0; b < blocks.length; b++) {
        final flat = (blocks[b][0] / 8).round() + 128;
        final originX = (b % 4) * 8;
        final originY = (b ~/ 4) * 8;
        final actual = image.pixels[originY * 32 + originX];
        expect(actual, closeTo(flat.clamp(0, 255), 1), reason: 'block $b');
      }
    });
  });
}
