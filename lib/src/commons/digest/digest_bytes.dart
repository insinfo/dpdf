import 'dart:math' as math;
import 'dart:typed_data';
import 'keccak_digest.dart';
import 'legacy_digest.dart';

/// Byte-oriented digest functions implemented from FIPS 180-4 and RFC 1321.
/// MD5 and SHA-1 are retained for legacy PDF formats, not new security designs.
abstract final class DigestBytes {
  static Uint8List compute(String algorithm, Uint8List input) {
    switch (algorithm.toUpperCase().replaceAll(RegExp(r'[-/]'), '')) {
      case 'MD5':
        return _md5(input);
      case 'SHA1':
        return _sha1(input);
      case 'SHA256':
        return _sha256(input);
      case 'SHA224':
        return _sha256(input, shortened: true);
      case 'SHA384':
        return _sha512(input, shortened: true);
      case 'SHA512':
        return _sha512(input, shortened: false);
      case 'SHA3224':
        return KeccakDigest.sha3(input, 224);
      case 'SHA3256':
        return KeccakDigest.sha3(input, 256);
      case 'SHA3384':
        return KeccakDigest.sha3(input, 384);
      case 'SHA3512':
        return KeccakDigest.sha3(input, 512);
      case 'SHAKE128':
        return KeccakDigest.shake(input, 128, 32);
      case 'SHAKE256':
        return KeccakDigest.shake(input, 256, 64);
      case 'MD2':
      case 'RIPEMD128':
      case 'RIPEMD160':
      case 'RIPEMD256':
        return LegacyDigest.compute(algorithm, input);
      default:
        throw ArgumentError.value(
            algorithm, 'algorithm', 'Digest not implemented.');
    }
  }

  static const _mask32 = 0xffffffff;
  static int _left(int value, int count) =>
      ((value << count) | (value >>> (32 - count))) & _mask32;
  static int _right(int value, int count) =>
      ((value >>> count) | (value << (32 - count))) & _mask32;

  static ByteData _padded(Uint8List input, int block, int lengthBytes,
      [Endian order = Endian.big]) {
    final size =
        ((input.length + 1 + lengthBytes + block - 1) ~/ block) * block;
    final bytes = Uint8List(size)..setRange(0, input.length, input);
    bytes[input.length] = 0x80;
    var bitLength = BigInt.from(input.length) << 3;
    for (var index = 0; index < lengthBytes; index++) {
      final position =
          order == Endian.big ? size - index - 1 : size - lengthBytes + index;
      bytes[position] = (bitLength & BigInt.from(255)).toInt();
      bitLength >>= 8;
    }
    return ByteData.sublistView(bytes);
  }

  static Uint8List _serialize32(List<int> state, Endian order) {
    final result = ByteData(state.length * 4);
    for (var index = 0; index < state.length; index++) {
      result.setUint32(index * 4, state[index], order);
    }
    return result.buffer.asUint8List();
  }

  static Uint8List _sha1(Uint8List input) {
    final message = _padded(input, 64, 8);
    final state = <int>[
      0x67452301,
      0xefcdab89,
      0x98badcfe,
      0x10325476,
      0xc3d2e1f0
    ];
    final schedule = Uint32List(80);
    const offsets = [0x5a827999, 0x6ed9eba1, 0x8f1bbcdc, 0xca62c1d6];
    for (var block = 0; block < message.lengthInBytes; block += 64) {
      for (var index = 0; index < 80; index++) {
        schedule[index] = index < 16
            ? message.getUint32(block + index * 4)
            : _left(
                schedule[index - 3] ^
                    schedule[index - 8] ^
                    schedule[index - 14] ^
                    schedule[index - 16],
                1);
      }
      var a = state[0], b = state[1], c = state[2], d = state[3], e = state[4];
      for (var round = 0; round < 80; round++) {
        final section = round ~/ 20;
        final function = section == 0
            ? (b & c) ^ (~b & d)
            : section == 2
                ? (b & c) ^ (b & d) ^ (c & d)
                : b ^ c ^ d;
        final next =
            (_left(a, 5) + function + e + offsets[section] + schedule[round]) &
                _mask32;
        e = d;
        d = c;
        c = _left(b, 30);
        b = a;
        a = next;
      }
      final working = [a, b, c, d, e];
      for (var index = 0; index < state.length; index++) {
        state[index] = (state[index] + working[index]) & _mask32;
      }
    }
    return _serialize32(state, Endian.big);
  }

  static final List<int> _md5Offsets = List.generate(
      64, (index) => (math.sin(index + 1).abs() * 4294967296).floor());

  static Uint8List _md5(Uint8List input) {
    final message = _padded(input, 64, 8, Endian.little);
    final state = <int>[0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476];
    const shifts = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];
    for (var block = 0; block < message.lengthInBytes; block += 64) {
      var a = state[0], b = state[1], c = state[2], d = state[3];
      for (var round = 0; round < 64; round++) {
        final section = round ~/ 16;
        final word = switch (section) {
          0 => round,
          1 => (5 * round + 1) % 16,
          2 => (3 * round + 5) % 16,
          _ => (7 * round) % 16
        };
        final function = switch (section) {
          0 => (b & c) | (~b & d),
          1 => (b & d) | (c & ~d),
          2 => b ^ c ^ d,
          _ => c ^ (b | ~d)
        };
        final sum = (a +
                function +
                _md5Offsets[round] +
                message.getUint32(block + word * 4, Endian.little)) &
            _mask32;
        final next =
            (b + _left(sum, shifts[section * 4 + round % 4])) & _mask32;
        a = d;
        d = c;
        c = b;
        b = next;
      }
      final working = [a, b, c, d];
      for (var index = 0; index < 4; index++) {
        state[index] = (state[index] + working[index]) & _mask32;
      }
    }
    return _serialize32(state, Endian.little);
  }

  // Derive the SHA-2 constants from fractional roots of primes using exact
  // integer arithmetic, avoiding floating-point rounding of 64-bit constants.
  static final List<int> _primes = () {
    final result = <int>[];
    for (var value = 2; result.length < 80; value++) {
      if (result.every((prime) => value % prime != 0)) result.add(value);
    }
    return result;
  }();

  static BigInt _fractionalRoot(int value, int degree, int bits) {
    final target = BigInt.from(value) << (degree * bits);
    var low = BigInt.zero;
    var high = BigInt.one << ((target.bitLength + degree - 1) ~/ degree);
    while (high - low > BigInt.one) {
      final middle = (low + high) >> 1;
      if (middle.pow(degree) <= target) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return low & ((BigInt.one << bits) - BigInt.one);
  }

  static final _sha256Offsets = _primes
      .take(64)
      .map((prime) => _fractionalRoot(prime, 3, 32).toInt())
      .toList();
  static final _sha256Initial = _primes
      .take(8)
      .map((prime) => _fractionalRoot(prime, 2, 32).toInt())
      .toList();
  static final _sha224Initial = _primes
      .skip(8)
      .take(8)
      .map((prime) =>
          (_fractionalRoot(prime, 2, 64) & BigInt.from(_mask32)).toInt())
      .toList();

  static Uint8List _sha256(Uint8List input, {bool shortened = false}) {
    final message = _padded(input, 64, 8);
    final state = List<int>.of(shortened ? _sha224Initial : _sha256Initial);
    final schedule = Uint32List(64);
    for (var block = 0; block < message.lengthInBytes; block += 64) {
      for (var index = 0; index < 64; index++) {
        if (index < 16) {
          schedule[index] = message.getUint32(block + index * 4);
        } else {
          final x = schedule[index - 15], y = schedule[index - 2];
          schedule[index] = (schedule[index - 16] +
                  schedule[index - 7] +
                  (_right(x, 7) ^ _right(x, 18) ^ (x >>> 3)) +
                  (_right(y, 17) ^ _right(y, 19) ^ (y >>> 10))) &
              _mask32;
        }
      }
      final work = List<int>.of(state);
      for (var round = 0; round < 64; round++) {
        final a = work[0],
            b = work[1],
            c = work[2],
            e = work[4],
            f = work[5],
            g = work[6];
        final first = (work[7] +
                (_right(e, 6) ^ _right(e, 11) ^ _right(e, 25)) +
                ((e & f) ^ (~e & g)) +
                _sha256Offsets[round] +
                schedule[round]) &
            _mask32;
        final second = ((_right(a, 2) ^ _right(a, 13) ^ _right(a, 22)) +
                ((a & b) ^ (a & c) ^ (b & c))) &
            _mask32;
        for (var index = 7; index > 0; index--) {
          work[index] = work[index - 1];
        }
        work[4] = (work[4] + first) & _mask32;
        work[0] = (first + second) & _mask32;
      }
      for (var index = 0; index < 8; index++) {
        state[index] = (state[index] + work[index]) & _mask32;
      }
    }
    return _serialize32(shortened ? state.sublist(0, 7) : state, Endian.big);
  }

  static final _mask64 = (BigInt.one << 64) - BigInt.one;
  static final _sha512Offsets =
      _primes.map((prime) => _fractionalRoot(prime, 3, 64)).toList();
  static final _sha512Initial =
      _primes.take(8).map((prime) => _fractionalRoot(prime, 2, 64)).toList();
  static final _sha384Initial = _primes
      .skip(8)
      .take(8)
      .map((prime) => _fractionalRoot(prime, 2, 64))
      .toList();
  static BigInt _rotate64(BigInt value, int count) =>
      ((value >> count) | (value << (64 - count))) & _mask64;

  static Uint8List _sha512(Uint8List input, {required bool shortened}) {
    final message = _padded(input, 128, 16);
    final state = List<BigInt>.of(shortened ? _sha384Initial : _sha512Initial);
    final schedule = List<BigInt>.filled(80, BigInt.zero);
    for (var block = 0; block < message.lengthInBytes; block += 128) {
      for (var index = 0; index < 80; index++) {
        if (index < 16) {
          final offset = block + index * 8;
          schedule[index] = (BigInt.from(message.getUint32(offset)) << 32) |
              BigInt.from(message.getUint32(offset + 4));
        } else {
          final x = schedule[index - 15], y = schedule[index - 2];
          schedule[index] = (schedule[index - 16] +
                  schedule[index - 7] +
                  (_rotate64(x, 1) ^ _rotate64(x, 8) ^ (x >> 7)) +
                  (_rotate64(y, 19) ^ _rotate64(y, 61) ^ (y >> 6))) &
              _mask64;
        }
      }
      final work = List<BigInt>.of(state);
      for (var round = 0; round < 80; round++) {
        final a = work[0],
            b = work[1],
            c = work[2],
            e = work[4],
            f = work[5],
            g = work[6];
        final first = (work[7] +
                (_rotate64(e, 14) ^ _rotate64(e, 18) ^ _rotate64(e, 41)) +
                ((e & f) ^ (~e & g)) +
                _sha512Offsets[round] +
                schedule[round]) &
            _mask64;
        final second =
            ((_rotate64(a, 28) ^ _rotate64(a, 34) ^ _rotate64(a, 39)) +
                    ((a & b) ^ (a & c) ^ (b & c))) &
                _mask64;
        for (var index = 7; index > 0; index--) {
          work[index] = work[index - 1];
        }
        work[4] = (work[4] + first) & _mask64;
        work[0] = (first + second) & _mask64;
      }
      for (var index = 0; index < 8; index++) {
        state[index] = (state[index] + work[index]) & _mask64;
      }
    }
    final result = Uint8List(shortened ? 48 : 64);
    for (var index = 0; index < result.length; index++) {
      result[index] =
          ((state[index ~/ 8] >> (56 - 8 * (index % 8))) & BigInt.from(255))
              .toInt();
    }
    return result;
  }
}
