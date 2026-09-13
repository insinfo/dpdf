import 'dart:math';
import 'dart:typed_data';

import 'package:dpdf/src/io/image/jpeg_arithmetic_decoder.dart';
import 'package:dpdf/src/io/image/jpeg_decoder.dart';
import 'package:test/test.dart';

import 'jpeg_arithmetic_support.dart';

/// The bi-linear upsampling filter of T.81 J.1.1.2, written independently of
/// the decoder's copy: the left column and top line are kept, the right column
/// and bottom line are replicated, and the division truncates.
List<List<int>> expand(List<List<int>> source,
    {required bool horizontally, required bool vertically}) {
  var plane = source;
  if (horizontally) {
    plane = [
      for (final row in plane)
        [
          for (var x = 0; x < row.length; x++) ...[
            row[x],
            (row[x] + row[min(x + 1, row.length - 1)]) ~/ 2,
          ],
        ],
    ];
  }
  if (vertically) {
    final out = <List<int>>[];
    for (var y = 0; y < plane.length; y++) {
      final above = plane[y];
      final below = plane[min(y + 1, plane.length - 1)];
      out
        ..add([...above])
        ..add([
          for (var x = 0; x < above.length; x++) (above[x] + below[x]) ~/ 2,
        ]);
    }
    plane = out;
  }
  return plane;
}

/// Huffman-codes one lossless scan over [plane] with [predictor].
Uint8List _huffmanScan(List<List<int>> plane, int predictor, int initial) {
  final writer = HuffmanBitWriter();
  for (var y = 0; y < plane.length; y++) {
    for (var x = 0; x < plane[y].length; x++) {
      final int prediction;
      if (predictor == 0) {
        prediction = 0;
      } else if (y == 0) {
        prediction = x == 0 ? initial : plane[y][x - 1];
      } else if (x == 0) {
        prediction = plane[y - 1][0];
      } else {
        prediction = switch (predictor) {
          1 => plane[y][x - 1],
          2 => plane[y - 1][x],
          _ => plane[y - 1][x - 1],
        };
      }
      final raw = (plane[y][x] - prediction) & 0xFFFF;
      final difference = raw >= 0x8000 ? raw - 0x10000 : raw;
      if (difference == -32768) {
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
        writer.writeBits(
            difference < 0 ? difference + (1 << category) - 1 : difference,
            category);
      }
    }
  }
  return writer.finish();
}

/// Arithmetic-codes one lossless scan over [plane] with predictor 0, which is
/// what a differential frame uses (T.81 J.1.3.2).
Uint8List _arithmeticDifferentialScan(List<List<int>> plane) {
  final encoder = ArithmeticEncoder();
  final model = ArithmeticModelEncoder(encoder, JpegArithConditioning())
    ..resetDcStats(0);
  final categories = [
    for (var y = 0; y < plane.length; y++) List<int>.filled(plane[y].length, 0),
  ];
  for (var y = 0; y < plane.length; y++) {
    for (var x = 0; x < plane[y].length; x++) {
      final raw = plane[y][x] & 0xFFFF;
      final difference = raw >= 0x8000 ? raw - 0x10000 : raw;
      categories[y][x] = model.encodeLosslessDifference(
        0,
        x == 0 ? 0 : categories[y][x - 1],
        y == 0 ? 0 : categories[y - 1][x],
        difference,
      );
    }
  }
  return encoder.finish();
}

void main() {
  group('hierarchical JPEG, T.81 Annex J', () {
    /// A 4 x 4 base layer and the 8 x 8 image the sequence should produce.
    late List<List<int>> base;
    late List<List<int>> target;

    setUp(() {
      final random = Random(1981);
      base = [
        for (var y = 0; y < 4; y++)
          [for (var x = 0; x < 4; x++) 40 + x * 30 + y * 20],
      ];
      target = [
        for (var y = 0; y < 8; y++)
          [for (var x = 0; x < 8; x++) 20 + random.nextInt(216)],
      ];
    });

    /// Builds SOI, DHP, the base frame, an EXP and the differential frame.
    Uint8List buildSequence({
      required bool expandHorizontally,
      required bool expandVertically,
      bool arithmeticDifferential = false,
    }) {
      final reference = expand(base,
          horizontally: expandHorizontally, vertically: expandVertically);
      final differences = [
        for (var y = 0; y < target.length; y++)
          [
            for (var x = 0; x < target[y].length; x++)
              target[y][x] -
                  reference[min(y, reference.length - 1)]
                      [min(x, reference[0].length - 1)],
          ],
      ];

      final builder = JpegBuilder()
        ..soi()
        ..dht(0, 0, FlatDcTable.counts, FlatDcTable.values);
      // DHP: the size of the completed image, B.3.2.
      builder.sof(0xDE, 8, target.length, target[0].length,
          const [FrameComponent(1, 1, 1)]);
      // The non-differential base frame.
      builder
        ..sof(0xC3, 8, base.length, base[0].length,
            const [FrameComponent(1, 1, 1)])
        ..sos(const [ScanComponent(1)], _huffmanScan(base, 1, 128),
            ss: 1, se: 0);
      if (expandHorizontally || expandVertically) {
        builder.exp(expandHorizontally ? 1 : 0, expandVertically ? 1 : 0);
      }
      // The differential frame: predictor 0, the difference coded directly.
      builder
        ..sof(arithmeticDifferential ? 0xCF : 0xC7, 8, target.length,
            target[0].length, const [FrameComponent(1, 1, 1)])
        ..sos(
            const [ScanComponent(1)],
            arithmeticDifferential
                ? _arithmeticDifferentialScan(differences)
                : _huffmanScan(differences, 0, 128),
            ss: 0,
            se: 0)
        ..eoi();
      return builder.build();
    }

    test('probe reports the size the DHP segment declares', () {
      final bytes =
          buildSequence(expandHorizontally: true, expandVertically: true);
      final info = JpegDecoder.probe(bytes);
      expect(info.decodable, isTrue);
      expect(info.width, equals(8));
      expect(info.height, equals(8));
    });

    test('expands the reference in both directions and adds the difference',
        () {
      final bytes =
          buildSequence(expandHorizontally: true, expandVertically: true);
      final image = JpegDecoder.decode(bytes);
      expect(image.width, equals(8));
      expect(image.height, equals(8));
      expect(image.pixels, equals([for (final row in target) ...row]));
    });

    test('the same sequence with an arithmetic differential frame', () {
      final bytes = buildSequence(
          expandHorizontally: true,
          expandVertically: true,
          arithmeticDifferential: true);
      expect(JpegDecoder.decode(bytes).pixels,
          equals([for (final row in target) ...row]));
    });

    test('expands only horizontally when Ev is zero', () {
      // The reference is 8 wide and 4 tall, so the bottom half of the frame
      // differs against a replicated last line.
      final bytes =
          buildSequence(expandHorizontally: true, expandVertically: false);
      expect(JpegDecoder.decode(bytes).pixels,
          equals([for (final row in target) ...row]));
    });

    test('expands only vertically when Eh is zero', () {
      final bytes =
          buildSequence(expandHorizontally: false, expandVertically: true);
      expect(JpegDecoder.decode(bytes).pixels,
          equals([for (final row in target) ...row]));
    });

    test('works without an EXP segment at all', () {
      final bytes =
          buildSequence(expandHorizontally: false, expandVertically: false);
      expect(JpegDecoder.decode(bytes).pixels,
          equals([for (final row in target) ...row]));
    });

    test('refuses a hierarchical sequence built on the DCT processes', () {
      final builder = JpegBuilder()
        ..soi()
        ..sof(0xDE, 8, 16, 16, const [FrameComponent(1, 1, 1)])
        ..sof(0xC0, 8, 16, 16, const [FrameComponent(1, 1, 1)])
        ..eoi();
      final info = JpegDecoder.probe(builder.build());
      expect(info.decodable, isFalse);
      expect(info.reason, contains('Hierarchical'));
    });

    test('rejects an EXP that asks for anything but a factor of two', () {
      final bytes =
          buildSequence(expandHorizontally: true, expandVertically: true);
      final at = _findMarker(bytes, 0xDF);
      expect(at, greaterThan(0));
      bytes[at + 4] = 0x21;
      expect(
          () => JpegDecoder.decode(bytes), throwsA(isA<JpegDecodeException>()));
    });
  });

  group('the upsampling filter of J.1.1.2', () {
    test('keeps the first column and interpolates towards the next', () {
      final source = [
        [0, 10, 100],
      ];
      expect(
          expand(source, horizontally: true, vertically: false),
          equals([
            [0, 5, 10, 55, 100, 100],
          ]));
    });

    test('replicates the bottom line for the last interpolation', () {
      final source = [
        [0],
        [8],
      ];
      expect(
          expand(source, horizontally: false, vertically: true),
          equals([
            [0],
            [4],
            [8],
            [8],
          ]));
    });
  });

  group('a three-layer hierarchical sequence', () {
    test('accumulates every differential frame in turn', () {
      final random = Random(90210);
      final layer0 = [
        for (var y = 0; y < 3; y++)
          [for (var x = 0; x < 3; x++) 50 + x * 25 + y * 15],
      ];
      final layer1 = [
        for (var y = 0; y < 6; y++)
          [for (var x = 0; x < 6; x++) 30 + random.nextInt(180)],
      ];
      final layer2 = [
        for (var y = 0; y < 12; y++)
          [for (var x = 0; x < 12; x++) 10 + random.nextInt(230)],
      ];

      List<List<int>> differenceAgainst(
          List<List<int>> reference, List<List<int>> wanted) {
        return [
          for (var y = 0; y < wanted.length; y++)
            [
              for (var x = 0; x < wanted[y].length; x++)
                wanted[y][x] -
                    reference[min(y, reference.length - 1)]
                        [min(x, reference[0].length - 1)],
            ],
        ];
      }

      final firstReference =
          expand(layer0, horizontally: true, vertically: true);
      final secondReference =
          expand(layer1, horizontally: true, vertically: true);

      final bytes = (JpegBuilder()
            ..soi()
            ..dht(0, 0, FlatDcTable.counts, FlatDcTable.values)
            ..sof(0xDE, 8, 12, 12, const [FrameComponent(1, 1, 1)])
            ..sof(0xC3, 8, 3, 3, const [FrameComponent(1, 1, 1)])
            ..sos(const [ScanComponent(1)], _huffmanScan(layer0, 1, 128),
                ss: 1, se: 0)
            ..exp(1, 1)
            ..sof(0xC7, 8, 6, 6, const [FrameComponent(1, 1, 1)])
            ..sos(const [ScanComponent(1)],
                _huffmanScan(differenceAgainst(firstReference, layer1), 0, 128),
                ss: 0, se: 0)
            ..exp(1, 1)
            ..sof(0xC7, 8, 12, 12, const [FrameComponent(1, 1, 1)])
            ..sos(const [
              ScanComponent(1)
            ], _huffmanScan(differenceAgainst(secondReference, layer2), 0, 128),
                ss: 0, se: 0)
            ..eoi())
          .build();

      final image = JpegDecoder.decode(bytes);
      expect(image.width, equals(12));
      expect(image.height, equals(12));
      expect(image.pixels, equals([for (final row in layer2) ...row]));
    });
  });
}

int _findMarker(Uint8List bytes, int code) {
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0xFF && bytes[i + 1] == code) return i;
  }
  return -1;
}
