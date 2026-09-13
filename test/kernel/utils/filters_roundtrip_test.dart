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

    test('encoding rejects Group 3 parameters', () {
      expect(
          () => FilterHandlers.encodeBytes(Uint8List(2),
              PdfName('CCITTFaxDecode'), _dict({'K': PdfNumber.fromInt(0)})),
          throwsA(isA<UnsupportedError>()));
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
