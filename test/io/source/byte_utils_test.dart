import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dpdf/dpdf.dart';

void main() {
  group('ByteUtils', () {
    group('getIsoBytesFromDouble', () {
      test('writes integer as int format', () {
        final bytes = ByteUtils.getIsoBytesFromDouble(42.0);
        expect(String.fromCharCodes(bytes), equals('42'));
      });

      test('writes negative integer', () {
        final bytes = ByteUtils.getIsoBytesFromDouble(-123.0);
        expect(String.fromCharCodes(bytes), equals('-123'));
      });

      test('writes zero', () {
        final bytes = ByteUtils.getIsoBytesFromDouble(0.0);
        expect(String.fromCharCodes(bytes), equals('0'));
      });

      test('writes decimal number', () {
        final bytes = ByteUtils.getIsoBytesFromDouble(3.14);
        final str = String.fromCharCodes(bytes);
        expect(double.parse(str), closeTo(3.14, 0.001));
      });

      test('writes small decimal', () {
        final bytes = ByteUtils.getIsoBytesFromDouble(0.001);
        final str = String.fromCharCodes(bytes);
        expect(double.parse(str), closeTo(0.001, 0.0001));
      });

      test('writes large number', () {
        final bytes = ByteUtils.getIsoBytesFromDouble(1000000.0);
        expect(String.fromCharCodes(bytes), equals('1000000'));
      });
    });

    group('getIsoBytesFromInt', () {
      test('writes positive int', () {
        final bytes = ByteUtils.getIsoBytesFromInt(12345);
        expect(String.fromCharCodes(bytes), equals('12345'));
      });

      test('writes negative int', () {
        final bytes = ByteUtils.getIsoBytesFromInt(-999);
        expect(String.fromCharCodes(bytes), equals('-999'));
      });

      test('writes zero', () {
        final bytes = ByteUtils.getIsoBytesFromInt(0);
        expect(String.fromCharCodes(bytes), equals('0'));
      });

      test('writes max int', () {
        final bytes = ByteUtils.getIsoBytesFromInt(2147483647);
        expect(String.fromCharCodes(bytes), equals('2147483647'));
      });
    });

    group('random number writing', () {
      test('random positive doubles round trip', () {
        final rnd = Random(42); // Seeded for reproducibility
        for (var i = 0; i < 100; i++) {
          final d = rnd.nextDouble() * 10000;
          final rounded = (d * 100).round() / 100; // Round to 2 decimal places
          if (rounded < 1.02) continue;

          final bytes = ByteUtils.getIsoBytesFromDouble(rounded);
          final str = String.fromCharCodes(bytes);
          final parsed = double.parse(str);
          expect(parsed, closeTo(rounded, 0.01),
              reason: 'Original: $rounded, String: $str');
        }
      });

      test('random small decimals round trip', () {
        final rnd = Random(42);
        for (var i = 0; i < 100; i++) {
          final d = rnd.nextDouble();
          final rounded =
              (d * 100000).round() / 100000; // Round to 5 decimal places
          if (rounded.abs() < 0.000015) continue;

          final bytes = ByteUtils.getIsoBytesFromDouble(rounded);
          final str = String.fromCharCodes(bytes);
          final parsed = double.parse(str);
          expect(parsed, closeTo(rounded, 0.00001),
              reason: 'Original: $rounded, String: $str');
        }
      });
    });

    group('special values', () {
      test('handles NaN by converting to 0', () {
        final bytes = ByteUtils.getIsoBytesFromDouble(double.nan);
        expect(String.fromCharCodes(bytes), equals('0'));
      });

      test('handles infinity by converting to large value or 0', () {
        final bytes = ByteUtils.getIsoBytesFromDouble(double.infinity);
        // Implementation-dependent, but should not crash
        expect(bytes.isNotEmpty, isTrue);
      });
    });
  });

  group('ByteBuffer', () {
    test('creates buffer with default capacity', () {
      final buf = ByteBuffer();
      expect(buf.isEmpty(), isTrue);
    });

    test('creates buffer with specified capacity', () {
      final buf = ByteBuffer.withCapacity(100);
      expect(buf.capacity(), equals(100));
    });

    test('appends single bytes', () {
      final buf = ByteBuffer();
      buf.append(65); // 'A'
      buf.append(66); // 'B'
      buf.append(67); // 'C'
      expect(buf.size(), equals(3));
      expect(String.fromCharCodes(buf.toByteArray()), equals('ABC'));
    });

    test('appends byte array', () {
      final buf = ByteBuffer();
      buf.appendBytes(Uint8List.fromList([72, 101, 108, 108, 111]));
      expect(String.fromCharCodes(buf.toByteArray()), equals('Hello'));
    });

    test('appends string', () {
      final buf = ByteBuffer();
      buf.appendString('World');
      expect(String.fromCharCodes(buf.toByteArray()), equals('World'));
    });

    test('reset clears buffer', () {
      final buf = ByteBuffer();
      buf.appendString('Hello');
      buf.reset();
      expect(buf.isEmpty(), isTrue);
      expect(buf.size(), equals(0));
    });

    test('toByteArray returns copy', () {
      final buf = ByteBuffer();
      buf.appendString('Test');
      final bytes = buf.toByteArray();
      expect(bytes.length, equals(4));
      expect(String.fromCharCodes(bytes), equals('Test'));
    });

    test('getInternalBuffer returns internal buffer', () {
      final buf = ByteBuffer();
      buf.appendString('ABC');
      final internal = buf.getInternalBuffer();
      expect(internal, isNotNull);
      expect(internal[0], equals(65)); // 'A'
    });

    test('getHex converts hex characters', () {
      expect(ByteBuffer.getHex('0'.codeUnitAt(0)), equals(0));
      expect(ByteBuffer.getHex('9'.codeUnitAt(0)), equals(9));
      expect(ByteBuffer.getHex('a'.codeUnitAt(0)), equals(10));
      expect(ByteBuffer.getHex('f'.codeUnitAt(0)), equals(15));
      expect(ByteBuffer.getHex('A'.codeUnitAt(0)), equals(10));
      expect(ByteBuffer.getHex('F'.codeUnitAt(0)), equals(15));
    });

    test('get retrieves byte at index', () {
      final buf = ByteBuffer();
      buf.appendString('ABC');
      expect(buf.get(0), equals(65)); // 'A'
      expect(buf.get(1), equals(66)); // 'B'
      expect(buf.get(2), equals(67)); // 'C'
    });

    test('expands capacity automatically', () {
      final buf = ByteBuffer.withCapacity(4);
      buf.appendString('Hello World!'); // 12 characters
      expect(buf.size(), equals(12));
      expect(String.fromCharCodes(buf.toByteArray()), equals('Hello World!'));
    });
  });
}
