import 'dart:math';
import 'dart:typed_data';

import 'package:dpdf/src/io/image/jpeg_arithmetic_decoder.dart';
import 'package:test/test.dart';

import 'jpeg_arithmetic_support.dart';

void main() {
  group('Table D.3, the probability estimation state machine', () {
    test('has the 113 entries the specification lists', () {
      expect(JpegArithmeticDecoder.stateCount, equals(113));
    });

    test('matches the values printed in the specification', () {
      // Index, Qe, Next_Index_LPS, Next_Index_MPS, Switch_MPS, read off the
      // rows of Table D.3 that anchor each of its sub-sequences.
      const rows = <List<int>>[
        [0, 0x5A1D, 1, 1, 1],
        [1, 0x2586, 14, 2, 0],
        [13, 0x0001, 12, 13, 0],
        [14, 0x5A7F, 15, 15, 1],
        [35, 0x002C, 33, 9, 0],
        [36, 0x5AE1, 37, 37, 1],
        [63, 0x008F, 61, 32, 0],
        [64, 0x5B12, 65, 65, 1],
        [79, 0x0A40, 77, 48, 0],
        [80, 0x5832, 80, 81, 1],
        [87, 0x2516, 86, 71, 0],
        [88, 0x5570, 88, 89, 1],
        [95, 0x56A8, 95, 96, 1],
        [100, 0x375E, 99, 93, 0],
        [105, 0x5627, 105, 106, 1],
        [110, 0x5A10, 110, 111, 1],
        [112, 0x59EB, 112, 111, 1],
      ];
      for (final row in rows) {
        expect(JpegArithmeticDecoder.stateRow(row[0]), equals(row.sublist(1)),
            reason: 'row ${row[0]}');
      }
    });

    test('keeps every next-index inside the table', () {
      for (var i = 0; i < JpegArithmeticDecoder.stateCount; i++) {
        final row = JpegArithmeticDecoder.stateRow(i);
        expect(row[0], inInclusiveRange(1, 0x5FFF));
        expect(row[1], inInclusiveRange(0, 112));
        expect(row[2], inInclusiveRange(0, 112));
        expect(row[3], inInclusiveRange(0, 1));
      }
    });
  });

  group('the binary arithmetic coder of Annex D', () {
    /// Encodes [decisions] against [contexts] contexts and decodes them back.
    void roundTrip(List<int> decisions, List<int> contexts) {
      final encoder = ArithmeticEncoder();
      final encodeStats = Uint8List(64);
      for (var i = 0; i < decisions.length; i++) {
        encoder.code(encodeStats, contexts[i], decisions[i]);
      }
      final bytes = encoder.finish();

      final decoder = JpegArithmeticDecoder(bytes, 0);
      final decodeStats = Uint8List(64);
      final decoded = <int>[];
      for (var i = 0; i < decisions.length; i++) {
        decoded.add(decoder.decode(decodeStats, contexts[i]));
      }
      expect(decoded, equals(decisions));
      expect(decodeStats, equals(encodeStats),
          reason: 'the two probability estimators must stay in step');
    }

    test('round-trips a fair coin on one context', () {
      final random = Random(20250913);
      final decisions = List.generate(4000, (_) => random.nextInt(2));
      roundTrip(decisions, List.filled(decisions.length, 0));
    });

    test('round-trips a heavily skewed source', () {
      final random = Random(7);
      final decisions =
          List.generate(20000, (_) => random.nextInt(200) == 0 ? 1 : 0);
      roundTrip(decisions, List.filled(decisions.length, 0));
    });

    test('round-trips an all-ones source', () {
      roundTrip(List.filled(50000, 1), List.filled(50000, 0));
    });

    test('stuffs a zero after every 0xFF it emits', () {
      // Random decisions over several contexts drive the code register through
      // runs of one bits, which is what produces X'FF' output bytes.
      final random = Random(3);
      final encoder = ArithmeticEncoder();
      final stats = Uint8List(64);
      final decisions = <int>[];
      final contexts = <int>[];
      for (var i = 0; i < 20000; i++) {
        final context = random.nextInt(8);
        final decision = random.nextInt(2);
        contexts.add(context);
        decisions.add(decision);
        encoder.code(stats, context, decision);
      }
      final bytes = encoder.finish();
      var stuffed = 0;
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] != 0xFF) continue;
        expect(i + 1, lessThan(bytes.length));
        expect(bytes[i + 1], equals(0),
            reason: 'every 0xFF must be followed by a stuffed zero');
        stuffed++;
      }
      expect(stuffed, greaterThan(0));

      // And the stuffing must be transparent to the decoder.
      final decoder = JpegArithmeticDecoder(bytes, 0);
      final decodeStats = Uint8List(64);
      for (var i = 0; i < decisions.length; i++) {
        expect(decoder.decode(decodeStats, contexts[i]), equals(decisions[i]),
            reason: 'decision $i');
      }
    });

    test('round-trips across many interleaved contexts', () {
      final random = Random(99);
      final decisions = <int>[];
      final contexts = <int>[];
      for (var i = 0; i < 30000; i++) {
        final context = random.nextInt(64);
        contexts.add(context);
        decisions.add(random.nextInt(context + 2) == 0 ? 1 : 0);
      }
      roundTrip(decisions, contexts);
    });

    test('feeds zeroes once the terminating marker is reached', () {
      // Two bytes of data then an EOI marker. Decoding past the end must keep
      // producing decisions rather than running off the buffer, per D.2.6.
      final bytes = Uint8List.fromList([0x00, 0x00, 0xFF, 0xD9]);
      final decoder = JpegArithmeticDecoder(bytes, 0);
      final stats = Uint8List(4);
      for (var i = 0; i < 500; i++) {
        expect(decoder.decode(stats, 0), inInclusiveRange(0, 1));
      }
      expect(decoder.markerReached, isTrue);
      expect(decoder.position, equals(2));
    });
  });

  group('DAC conditioning, T.81 B.2.4.3', () {
    test('starts at the defaults the SOI marker establishes', () {
      final conditioning = JpegArithConditioning();
      for (var i = 0; i < 4; i++) {
        expect(conditioning.dcL[i], equals(0));
        expect(conditioning.dcU[i], equals(1));
        expect(conditioning.acKx[i], equals(5));
      }
    });

    test('reads Cs as L + 16 * U for a DC table', () {
      final conditioning = JpegArithConditioning();
      conditioning.apply(0, 2, 0x53); // U = 5, L = 3.
      expect(conditioning.dcL[2], equals(3));
      expect(conditioning.dcU[2], equals(5));
      expect(conditioning.dcL[0], equals(0), reason: 'other tables untouched');
    });

    test('reads Cs as Kx for an AC table', () {
      final conditioning = JpegArithConditioning();
      conditioning.apply(1, 1, 13);
      expect(conditioning.acKx[1], equals(13));
    });

    test('rejects L greater than U, and Kx outside 1..63', () {
      final conditioning = JpegArithConditioning();
      expect(() => conditioning.apply(0, 0, 0x05), throwsArgumentError);
      expect(() => conditioning.apply(1, 0, 0), throwsArgumentError);
      expect(() => conditioning.apply(1, 0, 64), throwsArgumentError);
      expect(() => conditioning.apply(2, 0, 1), throwsArgumentError);
      expect(() => conditioning.apply(0, 4, 0x11), throwsArgumentError);
    });
  });
}
