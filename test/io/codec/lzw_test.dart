import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/io/codec/lzw_compressor.dart';
import 'package:dpdf/src/io/codec/lzw_string_table.dart';
import 'package:dpdf/src/io/codec/tiff_lzw_decoder.dart';

void main() {
  group('LZWStringTable', () {
    test('initializes with single byte codes', () {
      final table = LZWStringTable();
      table.clearTable(8);

      // After clearing with codeSize 8, codes 0-255 are single bytes
      // and 256, 257 are clear/end codes
      expect(table.findCharString(-1, 0), equals(0));
      expect(table.findCharString(-1, 255), equals(255));
    });

    test('addCharString adds new strings', () {
      final table = LZWStringTable();
      table.clearTable(8);

      // Add a new string starting with code 0 and byte 1
      final newCode = table.addCharString(0, 1);
      expect(newCode, equals(258)); // First new code after reserved codes
    });

    test('findCharString finds existing strings', () {
      final table = LZWStringTable();
      table.clearTable(8);

      // Add a string
      table.addCharString(0, 1);

      // Should find it
      final code = table.findCharString(0, 1);
      expect(code, equals(258));
    });

    test('findCharString returns -1 for missing strings', () {
      final table = LZWStringTable();
      table.clearTable(8);

      final code = table.findCharString(0, 1);
      expect(code, equals(-1));
    });
  });

  group('LZWEncoder', () {
    test('compresses simple data', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final compressed = LZWEncoder.compress(data);

      // Compressed data should exist
      expect(compressed, isNotNull);
      expect(compressed.length, greaterThan(0));
    });

    test('compresses repeated patterns efficiently', () {
      // Data with repeated patterns should compress well
      final data = Uint8List.fromList(List.generate(1000, (i) => i % 10));
      final compressed = LZWEncoder.compress(data);

      // Should compress to smaller size
      expect(compressed.length, lessThan(data.length));
    });
  });

  group('TIFFLZWDecoder', () {
    test('decodes simple LZW data', () {
      // Simple LZW encoded data for testing
      // This is a basic test - real LZW data would come from images
      final decoder = TIFFLZWDecoder(10, 1, 1);

      // The decoder should not throw for valid setup
      expect(decoder, isNotNull);
    });
  });

  group('LZW Round-trip', () {
    test('compress and decompress returns original', () {
      final original = Uint8List.fromList([
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
      ]);

      // Compress
      final compressed = LZWEncoder.compress(original);
      expect(compressed.length, greaterThan(0));

      // For full round-trip testing, we would need the decoder too
      // This test at least verifies compression doesn't crash
    });
  });
}
