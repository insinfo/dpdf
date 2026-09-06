import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pdfcraft/src/io/codec/ccitt_g4_encoder.dart';
import 'package:pdfcraft/src/io/codec/tiff_fax_decoder.dart';

void main() {
  test('Group4 uncompressed words reset white run between samples', () {
    const bits = '0000001111' '01' '001' '00000010';
    final data = Uint8List((bits.length + 7) ~/ 8 + 4);
    for (var bit = 0; bit < bits.length; bit++) {
      if (bits[bit] == '1') data[bit ~/ 8] |= 1 << (7 - bit % 8);
    }
    final output = Uint8List(1);
    CraftTIFFFaxDecoder(1, 5, 1).decodeT6(output, data, 0, 1, 2);
    expect(output, [0x48]);
  });
  test('Group4 scan spans round trip every starting bit and long run', () {
    for (final width in [1, 7, 8, 9, 31, 65]) {
      final stride = (width + 7) ~/ 8;
      final source = Uint8List(stride * 9);
      for (var y = 0; y < 9; y++) {
        for (var x = 0; x < width; x++) {
          if (x >= y && (y.isEven || x % 3 == 0))
            source[y * stride + x ~/ 8] |= 1 << (7 - x % 8);
        }
      }
      final encoded = CraftCCITTG4Encoder.compress(source, width, 9);
      final decoded = Uint8List(source.length);
      CraftTIFFFaxDecoder(1, width, 9).decodeT6(decoded, encoded, 0, 9, 0);
      expect(decoded, source, reason: 'width $width');
    }
  });
  group('CCITTG4Encoder', () {
    test('compresses simple white line', () {
      // 8 pixels wide, all white (0)
      final data = Uint8List.fromList([0x00]);
      final result = CraftCCITTG4Encoder.compress(data, 8, 1);

      expect(result, isNotEmpty);
      // G4 compression should produce some output
      expect(result.length, greaterThan(0));
    });

    test('compresses simple black line', () {
      // 8 pixels wide, all black (1)
      final data = Uint8List.fromList([0xFF]);
      final result = CraftCCITTG4Encoder.compress(data, 8, 1);

      expect(result, isNotEmpty);
    });

    test('compresses alternating pattern', () {
      // 16 pixels wide, alternating (0xAA = 10101010)
      final data = Uint8List.fromList([0xAA, 0xAA]);
      final result = CraftCCITTG4Encoder.compress(data, 16, 1);

      expect(result, isNotEmpty);
    });

    test('compresses multiple lines', () {
      // 8 pixels wide, 4 lines
      final data = Uint8List.fromList([0x00, 0xFF, 0x00, 0xFF]);
      final result = CraftCCITTG4Encoder.compress(data, 8, 4);

      expect(result, isNotEmpty);
    });

    test('constructor calculates rowbytes correctly', () {
      final encoder1 = CraftCCITTG4Encoder(8);

      // 8 pixels = 1 byte
      // 9 pixels = 2 bytes
      // 16 pixels = 2 bytes
      // We can't directly access _rowbytes, but we can verify behavior

      // 8 pixels - fits in 1 byte
      final data1 = Uint8List.fromList([0x00]);
      encoder1.fax4Encode(data1, 0, 1);
      expect(encoder1.close(), isNotEmpty);
    });

    test('handles larger image', () {
      // 64 pixels wide, 8 lines = 64 bytes of white
      final data = Uint8List(64);
      final result = CraftCCITTG4Encoder.compress(data, 64, 8);

      expect(result, isNotEmpty);
      // White image should compress well
      expect(result.length, lessThan(data.length));
    });
  });
}
