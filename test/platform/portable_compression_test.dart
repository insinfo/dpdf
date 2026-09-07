import 'dart:io' as native;
import 'dart:math';
import 'package:dpdf/src/platform/compression_portable.dart' as portable;
import 'package:test/test.dart';

void main() {
  test('fixed Huffman LZ77 reduces repetition and honors level zero', () {
    final text = List<int>.generate(
        120000, (i) => 'PDF portable text '[i % 18].codeUnitAt(0));
    for (final level in [-1, 1, 6, 9]) {
      final compressed = portable.ZLibEncoder(level: level).convert(text);
      expect(compressed.length, lessThan(text.length ~/ 20));
      expect(native.zlib.decode(compressed), text);
      expect(portable.zlib.decode(compressed), text);
    }
    final stored = const portable.ZLibEncoder(level: 0).convert(text);
    expect(stored.length, greaterThan(text.length));
    expect(native.zlib.decode(stored), text);
  });
  test('incompressible input selects stored blocks and distant matches decode',
      () {
    final rng = Random(872);
    final noise = List<int>.generate(65536, (_) => rng.nextInt(256));
    final compressed = portable.zlib.encode(noise);
    final stored = const portable.ZLibEncoder(level: 0).convert(noise);
    expect(compressed.length, lessThanOrEqualTo(stored.length));
    expect(native.zlib.decode(compressed), noise);
    for (final distance in [257, 4096, 32768, 32769]) {
      final input = [...noise.take(distance), ...noise.take(258)];
      expect(native.zlib.decode(portable.zlib.encode(input)), input);
    }
  });
  final random = Random(391);
  final vectors = <List<int>>[
    [],
    [0],
    List.generate(256, (i) => i),
    List.filled(100000, 65),
    List.generate(140000, (_) => random.nextInt(256)),
    List.generate(70000, (i) => (i * i ~/ 19) & 255),
  ];
  test('native stored, fixed and dynamic blocks decode portably', () {
    for (final data in vectors) {
      for (final level in [0, 1, 6, 9]) {
        for (final strategy in [0, 1, 2, 3, 4]) {
          final encoded = native.ZLibEncoder(level: level, strategy: strategy)
              .convert(data);
          expect(portable.zlib.decode(encoded), data);
        }
      }
      expect(portable.gzip.decode(native.gzip.encode(data)), data);
      expect(
          const portable.ZLibDecoder(raw: true)
              .convert(native.ZLibEncoder(raw: true).convert(data)),
          data);
    }
  });
  test('portable streams decode in SDK across block boundaries', () {
    for (final data in vectors) {
      expect(native.zlib.decode(portable.zlib.encode(data)), data);
      expect(native.gzip.decode(portable.gzip.encode(data)), data);
      expect(
          native.ZLibDecoder(raw: true)
              .convert(const portable.ZLibEncoder(raw: true).convert(data)),
          data);
    }
  });
  test('concatenated gzip members retain every member', () {
    final encoded = [
      ...native.gzip.encode([1, 2]),
      ...native.gzip.encode([3, 4])
    ];
    expect(portable.gzip.decode(encoded), [1, 2, 3, 4]);
  });
  test('checksum and truncation failures are explicit', () {
    for (final codec in [portable.zlib, portable.gzip]) {
      final encoded = codec.encode([1, 2, 3]);
      for (var length = 0; length < encoded.length; length++) {
        expect(() => codec.decode(encoded.sublist(0, length)),
            throwsFormatException);
      }
      encoded[encoded.length - 1] ^= 1;
      expect(() => codec.decode(encoded), throwsFormatException);
    }
    expect(() => const portable.ZLibDecoder(raw: true).convert([7]),
        throwsFormatException);
    expect(
        () =>
            const portable.ZLibDecoder(raw: true).convert([1, 1, 0, 0, 0, 42]),
        throwsFormatException);
  });
}
