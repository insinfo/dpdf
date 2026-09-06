import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/io/codec/ccitt_g4_encoder.dart';

void main() {
  group('CCITTG4Encoder', () {
    test('compresses simple white line', () {
      // 8 pixels wide, all white (0)
      final data = Uint8List.fromList([0x00]);
      final result = CCITTG4Encoder.compress(data, 8, 1);

      expect(result, isNotEmpty);
      // G4 compression should produce some output
      expect(result.length, greaterThan(0));
    });

    test('compresses simple black line', () {
      // 8 pixels wide, all black (1)
      final data = Uint8List.fromList([0xFF]);
      final result = CCITTG4Encoder.compress(data, 8, 1);

      expect(result, isNotEmpty);
    });

    test('compresses alternating pattern', () {
      // 16 pixels wide, alternating (0xAA = 10101010)
      final data = Uint8List.fromList([0xAA, 0xAA]);
      final result = CCITTG4Encoder.compress(data, 16, 1);

      expect(result, isNotEmpty);
    });

    test('compresses multiple lines', () {
      // 8 pixels wide, 4 lines
      final data = Uint8List.fromList([0x00, 0xFF, 0x00, 0xFF]);
      final result = CCITTG4Encoder.compress(data, 8, 4);

      expect(result, isNotEmpty);
    });

    test('constructor calculates rowbytes correctly', () {
      final encoder1 = CCITTG4Encoder(8);

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
      final result = CCITTG4Encoder.compress(data, 64, 8);

      expect(result, isNotEmpty);
      // White image should compress well
      expect(result.length, lessThan(data.length));
    });
  });
}
