import 'dart:typed_data';

/// Byte-oriented SHA-3 and SHAKE sponge, following FIPS 202.
/// Uses BigInt lanes so the 64-bit operations also work on Dart web targets.
abstract final class KeccakDigest {
  static final _mask = (BigInt.one << 64) - BigInt.one;
  static final _roundConstants = () {
    var register = 1;
    return List<BigInt>.generate(24, (_) {
      var value = BigInt.zero;
      for (var bit = 0; bit < 7; bit++) {
        if (register.isOdd) value ^= BigInt.one << ((1 << bit) - 1);
        register = ((register << 1) ^ ((register & 128) != 0 ? 0x71 : 0)) & 255;
      }
      return value;
    });
  }();

  static final _rotations = () {
    final values = List<int>.filled(25, 0);
    var x = 1, y = 0;
    for (var step = 0; step < 24; step++) {
      values[x + 5 * y] = ((step + 1) * (step + 2) ~/ 2) % 64;
      final nextY = (2 * x + 3 * y) % 5;
      x = y;
      y = nextY;
    }
    return values;
  }();

  static BigInt _rotate(BigInt value, int count) =>
      ((value << count) | (value >> (64 - count))) & _mask;

  static void _permute(List<BigInt> lanes) {
    final columns = List<BigInt>.filled(5, BigInt.zero);
    final shuffled = List<BigInt>.filled(25, BigInt.zero);
    for (final constant in _roundConstants) {
      for (var x = 0; x < 5; x++) {
        columns[x] = BigInt.zero;
        for (var y = 0; y < 5; y++) {
          columns[x] ^= lanes[x + 5 * y];
        }
      }
      for (var x = 0; x < 5; x++) {
        final correction =
            columns[(x + 4) % 5] ^ _rotate(columns[(x + 1) % 5], 1);
        for (var y = 0; y < 5; y++) {
          final index = x + 5 * y;
          shuffled[y + 5 * ((2 * x + 3 * y) % 5)] =
              _rotate(lanes[index] ^ correction, _rotations[index]);
        }
      }
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          lanes[x + 5 * y] = shuffled[x + 5 * y] ^
              (~shuffled[(x + 1) % 5 + 5 * y] & shuffled[(x + 2) % 5 + 5 * y]);
        }
      }
      lanes[0] ^= constant;
    }
  }

  static Uint8List sha3(Uint8List input, int bits) {
    if (![224, 256, 384, 512].contains(bits)) {
      throw ArgumentError.value(
          bits, 'bits', 'SHA-3 supports 224, 256, 384 or 512.');
    }
    return _sponge(input, (1600 - 2 * bits) ~/ 8, bits ~/ 8, 0x06);
  }

  static Uint8List shake(Uint8List input, int strength, int outputLength) {
    if (strength != 128 && strength != 256) {
      throw ArgumentError.value(strength, 'strength', 'Choose 128 or 256.');
    }
    RangeError.checkNotNegative(outputLength, 'outputLength');
    return _sponge(input, (1600 - 2 * strength) ~/ 8, outputLength, 0x1f);
  }

  static Uint8List _sponge(
      Uint8List input, int rate, int outputLength, int suffix) {
    final padded = Uint8List(((input.length + 1 + rate - 1) ~/ rate) * rate)
      ..setRange(0, input.length, input);
    padded[input.length] ^= suffix;
    padded[padded.length - 1] ^= 0x80;
    final lanes = List<BigInt>.filled(25, BigInt.zero);
    for (var offset = 0; offset < padded.length; offset += rate) {
      for (var index = 0; index < rate; index++) {
        lanes[index ~/ 8] ^=
            BigInt.from(padded[offset + index]) << (8 * (index % 8));
      }
      _permute(lanes);
    }
    final result = Uint8List(outputLength);
    for (var index = 0; index < outputLength; index++) {
      if (index != 0 && index % rate == 0) _permute(lanes);
      final position = index % rate;
      result[index] =
          ((lanes[position ~/ 8] >> (8 * (position % 8))) & BigInt.from(255))
              .toInt();
    }
    return result;
  }
}
