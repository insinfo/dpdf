import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// Packs an MSB-first bit string, padding the last byte with zeros.
Uint8List _bits(String bits) {
  final out = Uint8List((bits.length + 7) ~/ 8);
  for (var i = 0; i < bits.length; i++) {
    if (bits[i] == '1') out[i ~/ 8] |= 1 << (7 - i % 8);
  }
  return out;
}

/// Deterministic pseudo-random bytes, so a failure is reproducible.
Uint8List _noise(int length, [int seed = 1]) {
  final out = Uint8List(length);
  var state = seed;
  for (var i = 0; i < length; i++) {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    out[i] = (state >> 16) & 0xFF;
  }
  return out;
}

PdfDictionary _dict(Map<String, PdfObject> entries) {
  final dictionary = PdfDictionary();
  entries.forEach((key, value) => dictionary.put(PdfName(key), value));
  return dictionary;
}

Future<Uint8List> _roundTrip(Uint8List data, String filter,
    [PdfDictionary? parms]) async {
  final encoded = await FilterHandlers.encodeBytes(data, PdfName(filter), parms);
  final streamDictionary = PdfDictionary();
  streamDictionary.put(PdfName.filter, PdfName(filter));
  if (parms != null) streamDictionary.put(PdfName.decodeParms, parms);
  return FilterHandlers.decodeBytes(encoded, streamDictionary);
}

void main() {
  final samples = <String, Uint8List>{
    'empty': Uint8List(0),
    'single byte': Uint8List.fromList([0x42]),
    'all zeros': Uint8List(300),
    'all ones': Uint8List(300)..fillRange(0, 300, 0xFF),
    'ascending': Uint8List.fromList(List<int>.generate(256, (i) => i)),
    'noise': _noise(4096),
    'runs': Uint8List.fromList([
      ...List<int>.filled(200, 7),
      ...List<int>.generate(50, (i) => i),
      ...List<int>.filled(3, 0),
      ...List<int>.filled(129, 0xAB),
    ]),
  };

  group('ASCIIHexDecode round trip (7.4.2)', () {
    samples.forEach((name, data) {
      test('restores $name byte for byte', () async {
        expect(await _roundTrip(data, 'ASCIIHexDecode'), equals(data));
      });
    });

    test('encodes with the EOD marker and uppercase digits', () {
      final encoded =
          FilterHandlers.asciiHexEncode(Uint8List.fromList([0x00, 0xAB, 0xFF]));
      expect(String.fromCharCodes(encoded), equals('00ABFF>'));
    });

    test('decodes an odd number of digits as a trailing zero nibble', () {
      final decoded =
          FilterHandlers.asciiHexDecode(Uint8List.fromList('4A5>'.codeUnits));
      expect(decoded, equals([0x4A, 0x50]));
    });

    test('ignores white space between digits', () {
      final decoded = FilterHandlers.asciiHexDecode(
          Uint8List.fromList('4\n8 6\t5\r6C6C6F>'.codeUnits));
      expect(String.fromCharCodes(decoded), equals('Hello'));
    });
  });

  group('ASCII85Decode round trip (7.4.3)', () {
    samples.forEach((name, data) {
      test('restores $name byte for byte', () async {
        expect(await _roundTrip(data, 'ASCII85Decode'), equals(data));
      });
    });

    test('restores every partial final group', () async {
      for (var length = 0; length < 24; length++) {
        final data = _noise(length, length + 7);
        expect(await _roundTrip(data, 'ASCII85Decode'), equals(data),
            reason: 'length $length');
      }
    });

    test('writes z for a group of four zero bytes', () {
      final encoded = FilterHandlers.ascii85Encode(Uint8List(8));
      expect(String.fromCharCodes(encoded), equals('zz~>'));
    });

    test('matches the encoding of a known group', () {
      final encoded =
          FilterHandlers.ascii85Encode(Uint8List.fromList('Man '.codeUnits));
      expect(String.fromCharCodes(encoded), equals('9jqo^~>'));
    });

    test('stops at the EOD marker', () {
      final decoded = FilterHandlers.ascii85Decode(
          Uint8List.fromList('9jqo^~>ignored'.codeUnits));
      expect(String.fromCharCodes(decoded), equals('Man '));
    });
  });

  group('RunLengthDecode round trip (7.4.5)', () {
    samples.forEach((name, data) {
      test('restores $name byte for byte', () async {
        expect(await _roundTrip(data, 'RunLengthDecode'), equals(data));
      });
    });

    test('collapses a long run into repeat records', () {
      final encoded = FilterHandlers.runLengthEncode(Uint8List(300));
      // 300 zeros is two full 128 runs plus a 44 run, each two bytes, and EOD.
      expect(encoded.length, equals(7));
      expect(encoded.last, equals(128));
    });

    test('never emits a literal run longer than 128 bytes', () {
      final encoded = FilterHandlers.runLengthEncode(_noise(1000, 3));
      var index = 0;
      while (index < encoded.length) {
        final length = encoded[index];
        if (length == 128) break;
        expect(length, lessThan(128));
        index += length + 2;
      }
    });

    test('decodes the EOD byte as the end of data', () {
      final decoded = FilterHandlers.runLengthDecode(
          Uint8List.fromList([2, 1, 2, 3, 128, 0, 9]));
      expect(decoded, equals([1, 2, 3]));
    });
  });

  group('LZWDecode round trip (7.4.4.2)', () {
    samples.forEach((name, data) {
      test('restores $name byte for byte', () async {
        expect(await _roundTrip(data, 'LZWDecode'), equals(data));
      });
    });

    test('restores data with EarlyChange 0', () async {
      final parms = _dict({'EarlyChange': PdfNumber.fromInt(0)});
      for (final data in samples.values) {
        expect(await _roundTrip(data, 'LZWDecode', parms), equals(data));
      }
    });

    test('restores data long enough to grow the code length', () async {
      final data = _noise(70000, 11);
      expect(await _roundTrip(data, 'LZWDecode'), equals(data));
    });
  });

  group('FlateDecode round trip (7.4.4.1)', () {
    samples.forEach((name, data) {
      test('restores $name byte for byte', () async {
        expect(await _roundTrip(data, 'FlateDecode'), equals(data));
      });
    });
  });

  group('Predictors (7.4.4.4)', () {
    const columns = 17;

    Uint8List image(int colors, int bitsPerComponent, int rows, int seed) {
      final rowBytes = (columns * colors * bitsPerComponent + 7) ~/ 8;
      return _noise(rowBytes * rows, seed);
    }

    for (final predictor in [2, 10, 11, 12, 13, 14, 15]) {
      for (final colors in [1, 3, 4]) {
        for (final bits in [1, 2, 4, 8, 16]) {
          test('predictor $predictor survives $colors colors at $bits bpc',
              () async {
            final data = image(colors, bits, 5, predictor * 31 + colors + bits);
            final parms = _dict({
              'Predictor': PdfNumber.fromInt(predictor),
              'Colors': PdfNumber.fromInt(colors),
              'BitsPerComponent': PdfNumber.fromInt(bits),
              'Columns': PdfNumber.fromInt(columns),
            });
            expect(await _roundTrip(data, 'FlateDecode', parms), equals(data));
            expect(await _roundTrip(data, 'LZWDecode', parms), equals(data));
          });
        }
      }
    }

    test('TIFF predictor 2 subtracts the component to the left', () {
      final data = Uint8List.fromList([10, 20, 30, 40]);
      final encoded = FilterHandlers.applyPredictor(data,
          predictor: 2, colors: 1, bitsPerComponent: 8, columns: 4);
      expect(encoded, equals([10, 10, 10, 10]));
      expect(
          FilterHandlers.undoPredictor(encoded,
              predictor: 2, colors: 1, bitsPerComponent: 8, columns: 4),
          equals(data));
    });

    test('TIFF predictor 2 wraps 16-bit components at 65536', () {
      final data = Uint8List.fromList([0x00, 0x10, 0x00, 0x05]);
      final encoded = FilterHandlers.applyPredictor(data,
          predictor: 2, colors: 1, bitsPerComponent: 16, columns: 2);
      expect(encoded, equals([0x00, 0x10, 0xFF, 0xF5]));
      expect(
          FilterHandlers.undoPredictor(encoded,
              predictor: 2, colors: 1, bitsPerComponent: 16, columns: 2),
          equals(data));
    });

    test('TIFF predictor 2 works on 4-bit components', () {
      // Two samples per byte: 3, 1, 2, 4.
      final data = Uint8List.fromList([0x31, 0x24]);
      final encoded = FilterHandlers.applyPredictor(data,
          predictor: 2, colors: 1, bitsPerComponent: 4, columns: 4);
      // Differences 3, -2, 1, 2 wrapped to four bits.
      expect(encoded, equals([0x3E, 0x12]));
      expect(
          FilterHandlers.undoPredictor(encoded,
              predictor: 2, colors: 1, bitsPerComponent: 4, columns: 4),
          equals(data));
    });

    test('PNG predictor 12 tags every row as Up', () {
      final data = _noise(40, 5);
      final encoded = FilterHandlers.applyPredictor(data,
          predictor: 12, colors: 1, bitsPerComponent: 8, columns: 10);
      expect(encoded.length, equals(44));
      for (var row = 0; row < 4; row++) {
        expect(encoded[row * 11], equals(2));
      }
    });

    test('PNG predictor 15 may pick a different filter per row', () {
      final rows = Uint8List(30);
      // Row 0 is flat, row 1 repeats row 0, row 2 is a ramp.
      for (var x = 0; x < 10; x++) {
        rows[x] = 9;
        rows[10 + x] = 9;
        rows[20 + x] = x * 3;
      }
      final encoded = FilterHandlers.applyPredictor(rows,
          predictor: 15, colors: 1, bitsPerComponent: 8, columns: 10);
      final tags = [encoded[0], encoded[11], encoded[22]];
      expect(tags[1], equals(2), reason: 'a repeated row is cheapest as Up');
      expect(
          FilterHandlers.undoPredictor(encoded,
              predictor: 15, colors: 1, bitsPerComponent: 8, columns: 10),
          equals(rows));
    });
  });

  group('CCITTFaxDecode (7.4.6)', () {
    Uint8List bilevel(int columns, int rows, int seed) {
      final rowBytes = (columns + 7) ~/ 8;
      final data = _noise(rowBytes * rows, seed);
      // Clear the padding bits so the comparison is meaningful.
      final spare = rowBytes * 8 - columns;
      if (spare > 0) {
        final mask = (0xFF << spare) & 0xFF;
        for (var row = 0; row < rows; row++) {
          data[row * rowBytes + rowBytes - 1] &= mask;
        }
      }
      return data;
    }

    /// An image whose runs are far longer than the 63 pixels a terminating
    /// code can spell, so the encoder has to reach for the makeup codes of
    /// T.4 tables 3 and 4.
    Uint8List longRuns(int columns, int rows) {
      final rowBytes = (columns + 7) ~/ 8;
      final data = Uint8List(rowBytes * rows);
      for (var row = 0; row < rows; row++) {
        // A black band that starts a little further right on every line, so
        // the two-dimensional modes have something to track as well.
        final from = (columns ~/ 8) + row;
        final to = columns - (columns ~/ 8);
        for (var x = from; x < to && x < columns; x++) {
          data[row * rowBytes + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
      return data;
    }

    /// The one pixel checkerboard: every run is a single pixel, which is the
    /// worst case for both schemes and the one that makes a two-dimensional
    /// line fall back to vertical codes on every column.
    Uint8List checkerboard(int columns, int rows) {
      final rowBytes = (columns + 7) ~/ 8;
      final data = Uint8List(rowBytes * rows);
      for (var row = 0; row < rows; row++) {
        for (var x = 0; x < columns; x++) {
          if ((x + row).isEven) {
            data[row * rowBytes + (x >> 3)] |= 0x80 >> (x & 7);
          }
        }
      }
      return data;
    }

    /// The parameters a `/CCITTFaxDecode` stream declares, and the encoder is
    /// handed, for one round trip.
    PdfDictionary ccittParms(int k, int columns, int rows,
            {bool encodedByteAlign = false,
            bool endOfLine = false,
            bool blackIs1 = false}) =>
        _dict({
          'K': PdfNumber.fromInt(k),
          'Columns': PdfNumber.fromInt(columns),
          'Rows': PdfNumber.fromInt(rows),
          if (encodedByteAlign) 'EncodedByteAlign': PdfBoolean(true),
          if (endOfLine) 'EndOfLine': PdfBoolean(true),
          if (blackIs1) 'BlackIs1': PdfBoolean(true),
        });

    for (final columns in [1, 8, 9, 64, 129]) {
      test('Group 4 round trip at $columns columns', () async {
        const rows = 12;
        final image = bilevel(columns, rows, columns + 3);
        final parms = _dict({
          'K': PdfNumber.fromInt(-1),
          'Columns': PdfNumber.fromInt(columns),
          'Rows': PdfNumber.fromInt(rows),
        });
        expect(
            await _roundTrip(image, 'CCITTFaxDecode', parms), equals(image));
      });
    }

    test('Group 4 round trip honours BlackIs1', () async {
      const columns = 40;
      const rows = 6;
      final image = bilevel(columns, rows, 77);
      final parms = _dict({
        'K': PdfNumber.fromInt(-1),
        'Columns': PdfNumber.fromInt(columns),
        'Rows': PdfNumber.fromInt(rows),
        'BlackIs1': PdfBoolean(true),
      });
      expect(await _roundTrip(image, 'CCITTFaxDecode', parms), equals(image));
    });

    test('Group 4 encoding of the same image differs by BlackIs1', () {
      final image = bilevel(16, 4, 12);
      final asWritten =
          FilterHandlers.ccittFaxEncode(image, columns: 16, rows: 4);
      final inverted = FilterHandlers.ccittFaxEncode(image,
          columns: 16, rows: 4, blackIs1: true);
      expect(asWritten, isNot(equals(inverted)));
    });

    test('Group 3 one-dimensional data decodes without EOL codes', () {
      // A single 8 pixel row: white run of 8.
      final decoded = FilterHandlers.ccittFaxDecode(_bits('10011'),
          k: 0, columns: 8, rows: 1);
      expect(decoded, equals([0xFF]));
    });

    test('Group 3 one-dimensional data decodes runs of both colours', () {
      // White run of 4 then black run of 4.
      final decoded = FilterHandlers.ccittFaxDecode(_bits('1011011'),
          k: 0, columns: 8, rows: 1);
      expect(decoded, equals([0xF0]));
      final asBlackIs1 = FilterHandlers.ccittFaxDecode(_bits('1011011'),
          k: 0, columns: 8, rows: 1, blackIs1: true);
      expect(asBlackIs1, equals([0x0F]));
    });

    test('EncodedByteAlign starts every Group 3 line on a byte boundary', () {
      // Without alignment the second row would begin inside the first byte.
      final data = Uint8List.fromList([0x98, 0xB6]);
      final aligned = FilterHandlers.ccittFaxDecode(data,
          k: 0, columns: 8, rows: 2, encodedByteAlign: true);
      expect(aligned, equals([0xFF, 0xF0]));

      final unaligned =
          FilterHandlers.ccittFaxDecode(data, k: 0, columns: 8, rows: 2);
      expect(unaligned, isNot(equals([0xFF, 0xF0])));
    });

    test('EncodedByteAlign round trips a Group 4 image', () async {
      const columns = 33;
      const rows = 7;
      final image = bilevel(columns, rows, 19);
      final encoder = <String, PdfObject>{
        'K': PdfNumber.fromInt(-1),
        'Columns': PdfNumber.fromInt(columns),
        'Rows': PdfNumber.fromInt(rows),
      };
      // The Group 4 encoder produces an unaligned stream, so alignment is only
      // checked to be a no-op when the data has no fill bits to skip.
      final encoded = await FilterHandlers.encodeBytes(
          image, PdfName('CCITTFaxDecode'), _dict(encoder));
      final decoded = FilterHandlers.ccittFaxDecode(encoded,
          k: -1, columns: columns, rows: rows);
      expect(decoded, equals(image));
    });

    test('mixed Group 3 two-dimensional data decodes tagged lines', () {
      final data = _bits('000000000001' '1' '10011' // EOL, 1-D tag, white 8
          '000000000001' '1' '1011' '011'); // EOL, 1-D tag, white 4, black 4
      final decoded =
          FilterHandlers.ccittFaxDecode(data, k: 4, columns: 8, rows: 2);
      expect(decoded, equals([0xFF, 0xF0]));
    });

    test('an absent Rows value trims to the rows actually decoded', () {
      const columns = 24;
      const rows = 5;
      final image = bilevel(columns, rows, 31);
      final encoded =
          FilterHandlers.ccittFaxEncode(image, columns: columns, rows: rows);
      final decoded =
          FilterHandlers.ccittFaxDecode(encoded, k: -1, columns: columns);
      expect(decoded.length, equals(image.length));
      expect(decoded, equals(image));
    });

    test('Rows falls back to the image dictionary Height', () async {
      const columns = 16;
      const rows = 4;
      final image = bilevel(columns, rows, 45);
      final encoded =
          FilterHandlers.ccittFaxEncode(image, columns: columns, rows: rows);
      final streamDictionary = PdfDictionary();
      streamDictionary.put(PdfName.filter, PdfName('CCITTFaxDecode'));
      streamDictionary.put(PdfName('Height'), PdfNumber.fromInt(rows));
      streamDictionary.put(
          PdfName.decodeParms,
          _dict({
            'K': PdfNumber.fromInt(-1),
            'Columns': PdfNumber.fromInt(columns),
          }));
      expect(await FilterHandlers.decodeBytes(encoded, streamDictionary),
          equals(image));
    });

    // Group 3, one-dimensional (K = 0) and mixed (K > 0). Only the sign of K
    // matters to the filter, so 2 and 4 stand for every positive value: they
    // differ only in how many two-dimensional lines follow each
    // one-dimensional one.
    for (final k in [0, 2, 4]) {
      final scheme = k == 0 ? 'Group 3 1-D' : 'mixed Group 3 (K = $k)';

      for (final columns in [1, 8, 9, 64, 129]) {
        test('$scheme round trip at $columns columns', () async {
          const rows = 12;
          final image = bilevel(columns, rows, columns + k + 3);
          expect(
              await _roundTrip(
                  image, 'CCITTFaxDecode', ccittParms(k, columns, rows)),
              equals(image));
        });
      }

      test('$scheme round trip with EndOfLine', () async {
        const columns = 37;
        const rows = 9;
        final image = bilevel(columns, rows, 91 + k);
        expect(
            await _roundTrip(image, 'CCITTFaxDecode',
                ccittParms(k, columns, rows, endOfLine: true)),
            equals(image));
      });

      test('$scheme round trip with EncodedByteAlign', () async {
        const columns = 37;
        const rows = 9;
        final image = bilevel(columns, rows, 92 + k);
        expect(
            await _roundTrip(image, 'CCITTFaxDecode',
                ccittParms(k, columns, rows, encodedByteAlign: true)),
            equals(image));
      });

      test('$scheme round trip with EndOfLine and EncodedByteAlign', () async {
        const columns = 37;
        const rows = 9;
        final image = bilevel(columns, rows, 93 + k);
        expect(
            await _roundTrip(
                image,
                'CCITTFaxDecode',
                ccittParms(k, columns, rows,
                    endOfLine: true, encodedByteAlign: true)),
            equals(image));
      });

      test('$scheme round trip honours BlackIs1', () async {
        const columns = 40;
        const rows = 6;
        final image = bilevel(columns, rows, 78 + k);
        expect(
            await _roundTrip(image, 'CCITTFaxDecode',
                ccittParms(k, columns, rows, blackIs1: true)),
            equals(image));
      });

      test('$scheme round trip of runs long enough to need makeup codes',
          () async {
        const columns = 2600;
        const rows = 8;
        final image = longRuns(columns, rows);
        expect(
            await _roundTrip(
                image, 'CCITTFaxDecode', ccittParms(k, columns, rows)),
            equals(image));
      });

      test('$scheme round trip of a one pixel checkerboard', () async {
        const columns = 101;
        const rows = 17;
        final image = checkerboard(columns, rows);
        expect(
            await _roundTrip(
                image, 'CCITTFaxDecode', ccittParms(k, columns, rows)),
            equals(image));
      });
    }

    test('Group 4 round trip of runs long enough to need makeup codes',
        () async {
      const columns = 2600;
      const rows = 8;
      final image = longRuns(columns, rows);
      expect(
          await _roundTrip(
              image, 'CCITTFaxDecode', ccittParms(-1, columns, rows)),
          equals(image));
    });

    test('Group 4 round trip of a one pixel checkerboard', () async {
      const columns = 101;
      const rows = 17;
      final image = checkerboard(columns, rows);
      expect(
          await _roundTrip(
              image, 'CCITTFaxDecode', ccittParms(-1, columns, rows)),
          equals(image));
    });

    test('EncodedByteAlign really aligns every Group 3 line', () {
      const columns = 37;
      const rows = 6;
      final image = bilevel(columns, rows, 55);
      final aligned = FilterHandlers.ccittFaxEncode(image,
          k: 0, columns: columns, rows: rows, encodedByteAlign: true);
      final packed = FilterHandlers.ccittFaxEncode(image,
          k: 0, columns: columns, rows: rows);
      expect(aligned.length, greaterThan(packed.length),
          reason: 'the fill bits have to cost something');
      // Decoding the aligned stream without the parameter reads the fill bits
      // as data, so the two decodes cannot agree.
      expect(
          FilterHandlers.ccittFaxDecode(aligned,
              k: 0, columns: columns, rows: rows, encodedByteAlign: true),
          equals(image));
      expect(
          FilterHandlers.ccittFaxDecode(aligned,
              k: 0, columns: columns, rows: rows),
          isNot(equals(image)));
    });

    test('EncodedByteAlign round trips a Group 4 image with real fill bits',
        () async {
      const columns = 33;
      const rows = 7;
      final image = bilevel(columns, rows, 19);
      final encoded = await FilterHandlers.encodeBytes(
          image,
          PdfName('CCITTFaxDecode'),
          ccittParms(-1, columns, rows, encodedByteAlign: true));
      expect(
          FilterHandlers.ccittFaxDecode(encoded,
              k: -1,
              columns: columns,
              rows: rows,
              encodedByteAlign: true),
          equals(image));
    });

    test('a Group 3 stream with EndOfLine opens with the EOL pattern', () {
      const columns = 24;
      const rows = 3;
      final image = bilevel(columns, rows, 61);
      final withEol = FilterHandlers.ccittFaxEncode(image,
          k: 0, columns: columns, rows: rows, endOfLine: true);
      // 000000000001 fills the first byte and a half.
      expect(withEol[0], equals(0x00));
      expect(withEol[1] & 0xF0, equals(0x10));
      final withoutEol = FilterHandlers.ccittFaxEncode(image,
          k: 0, columns: columns, rows: rows);
      expect(withoutEol[0], isNot(equals(0x00)));
    });

    test('every mixed Group 3 line carries its one or two dimensional tag',
        () {
      // Two lines, K = 2: the first is coded one-dimensionally and tagged 1,
      // the second two-dimensionally and tagged 0.
      const columns = 16;
      final image = bilevel(columns, 2, 88);
      final encoded =
          FilterHandlers.ccittFaxEncode(image, k: 2, columns: columns, rows: 2);
      var bit = 0;
      bool next() {
        final value = (encoded[bit >> 3] >> (7 - (bit & 7))) & 1;
        bit++;
        return value == 1;
      }

      int eolAt(int from) {
        for (var start = from; start + 13 <= encoded.length * 8; start++) {
          var zeros = 0;
          while (zeros < 11) {
            final value =
                (encoded[(start + zeros) >> 3] >> (7 - ((start + zeros) & 7))) &
                    1;
            if (value != 0) break;
            zeros++;
          }
          if (zeros == 11) {
            final one = (encoded[(start + 11) >> 3] >>
                    (7 - ((start + 11) & 7))) &
                1;
            if (one == 1) return start;
          }
        }
        return -1;
      }

      expect(eolAt(0), equals(0));
      bit = 12;
      expect(next(), isTrue, reason: 'the first line is one dimensional');
      final second = eolAt(13);
      expect(second, greaterThan(0));
      bit = second + 12;
      expect(next(), isFalse, reason: 'the second line is two dimensional');
    });

    test('the three schemes produce three different encodings', () {
      const columns = 64;
      const rows = 10;
      final image = bilevel(columns, rows, 101);
      final group4 = FilterHandlers.ccittFaxEncode(image,
          k: -1, columns: columns, rows: rows);
      final oneDimensional = FilterHandlers.ccittFaxEncode(image,
          k: 0, columns: columns, rows: rows);
      final mixed = FilterHandlers.ccittFaxEncode(image,
          k: 4, columns: columns, rows: rows);
      expect(group4, isNot(equals(oneDimensional)));
      expect(group4, isNot(equals(mixed)));
      expect(oneDimensional, isNot(equals(mixed)));
      // Two dimensional coding is what pays for itself, but only on an image
      // that has something for a reference line to predict: on noise, where
      // every line is unlike the one above it, Group 4 is the larger of the
      // three.
      final scan = longRuns(columns, rows);
      expect(
          FilterHandlers.ccittFaxEncode(scan,
                  k: -1, columns: columns, rows: rows)
              .length,
          lessThan(FilterHandlers.ccittFaxEncode(scan,
                  k: 0, columns: columns, rows: rows)
              .length));
    });

    for (final k in [0, 2, 4]) {
      for (final endOfLine in [false, true]) {
        final scheme = k == 0 ? 'Group 3 1-D' : 'mixed Group 3 (K = $k)';
        test(
            '$scheme with EndOfLine $endOfLine trims an absent Rows to the '
            'rows really decoded', () {
          const columns = 24;
          const rows = 5;
          final image = bilevel(columns, rows, 31);
          final encoded = FilterHandlers.ccittFaxEncode(image,
              k: k, columns: columns, rows: rows, endOfLine: endOfLine);
          final decoded = FilterHandlers.ccittFaxDecode(encoded,
              k: k, columns: columns, endOfLine: endOfLine);
          expect(decoded.length, equals(image.length));
          expect(decoded, equals(image));
        });
      }
    }

    test('encoding defaults to Group 4 when no K is given', () {
      const columns = 32;
      const rows = 5;
      final image = bilevel(columns, rows, 17);
      expect(
          FilterHandlers.ccittFaxEncode(image, columns: columns, rows: rows),
          equals(FilterHandlers.ccittFaxEncode(image,
              k: -1, columns: columns, rows: rows)));
    });
  });

  group('Filter chains', () {
    test('an array of filters decodes in order', () async {
      final data = _noise(5000, 21);
      final deflated = FilterHandlers.flateEncode(data);
      final encoded = FilterHandlers.ascii85Encode(deflated);

      final streamDictionary = PdfDictionary();
      streamDictionary.put(
          PdfName.filter,
          PdfArray.fromList(
              [PdfName('ASCII85Decode'), PdfName('FlateDecode')]));
      expect(await FilterHandlers.decodeBytes(encoded, streamDictionary),
          equals(data));
    });

    test('a chain with per-filter decode parameters decodes in order',
        () async {
      const columns = 12;
      final data = _noise(columns * 4, 22);
      final predicted = FilterHandlers.applyPredictor(data,
          predictor: 12, colors: 1, bitsPerComponent: 8, columns: columns);
      final encoded =
          FilterHandlers.asciiHexEncode(FilterHandlers.flateEncode(predicted));

      final streamDictionary = PdfDictionary();
      streamDictionary.put(
          PdfName.filter,
          PdfArray.fromList(
              [PdfName('ASCIIHexDecode'), PdfName('FlateDecode')]));
      streamDictionary.put(
          PdfName.decodeParms,
          PdfArray.fromList([
            PdfNull(),
            _dict({
              'Predictor': PdfNumber.fromInt(12),
              'Columns': PdfNumber.fromInt(columns),
            }),
          ]));
      expect(await FilterHandlers.decodeBytes(encoded, streamDictionary),
          equals(data));
    });

    test('the abbreviated filter names are accepted', () async {
      final data = Uint8List.fromList('abbreviated'.codeUnits);
      final streamDictionary = PdfDictionary();
      streamDictionary.put(PdfName.filter, PdfName('AHx'));
      expect(
          await FilterHandlers.decodeBytes(
              FilterHandlers.asciiHexEncode(data), streamDictionary),
          equals(data));
    });

    test('the Crypt filter leaves already decrypted data alone', () async {
      final data = _noise(64, 2);
      final streamDictionary = PdfDictionary();
      streamDictionary.put(PdfName.filter, PdfName('Crypt'));
      streamDictionary.put(
          PdfName.decodeParms, _dict({'Name': PdfName('Identity')}));
      expect(await FilterHandlers.decodeBytes(data, streamDictionary),
          equals(data));
    });

    test('image filters are passed through untouched', () async {
      final data = _noise(32, 4);
      for (final name in ['DCTDecode', 'JPXDecode']) {
        final streamDictionary = PdfDictionary();
        streamDictionary.put(PdfName.filter, PdfName(name));
        expect(await FilterHandlers.decodeBytes(data, streamDictionary),
            equals(data),
            reason: name);
      }
    });

    test('encoding an image filter is refused rather than silently wrong', () {
      for (final name in ['DCTDecode', 'JPXDecode', 'JBIG2Decode', 'Crypt']) {
        expect(() => FilterHandlers.encodeBytes(Uint8List(4), PdfName(name)),
            throwsA(isA<UnsupportedError>()),
            reason: name);
      }
    });
  });
}
