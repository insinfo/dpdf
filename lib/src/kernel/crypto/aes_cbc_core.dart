import 'dart:typed_data';

/// AES round transformations from FIPS 197, with a CBC chaining state.
class AesCbcCore {
  final bool encrypt;
  late final Uint8List _schedule;
  late final int _rounds;
  late Uint8List _chain;
  static int _multiply(int a, int b) {
    var result = 0;
    while (b != 0) {
      if ((b & 1) != 0) result ^= a;
      a = ((a << 1) ^ ((a & 128) == 0 ? 0 : 0x11b)) & 255;
      b >>= 1;
    }
    return result;
  }

  static int _substitute(int x) {
    var inverse = 0;
    if (x != 0) {
      inverse = 1;
      for (var i = 0; i < 254; i++) {
        inverse = _multiply(inverse, x);
      }
    }
    var value = inverse ^ 0x63;
    for (var i = 1; i <= 4; i++) {
      value ^= ((inverse << i) | (inverse >> (8 - i))) & 255;
    }
    return value;
  }

  static final _s = List<int>.generate(256, _substitute);
  static final _inverse = List<int>.generate(256, (i) => _s.indexOf(i));

  // Products of the MixColumns and InvMixColumns matrices, tabulated once so
  // the round transformation is a lookup instead of a carry-less multiply.
  static Uint8List _table(int factor) =>
      Uint8List.fromList(List<int>.generate(256, (i) => _multiply(i, factor)));
  static final Uint8List _mul2 = _table(2);
  static final Uint8List _mul3 = _table(3);
  static final Uint8List _mul9 = _table(9);
  static final Uint8List _mul11 = _table(11);
  static final Uint8List _mul13 = _table(13);
  static final Uint8List _mul14 = _table(14);

  AesCbcCore(this.encrypt, Uint8List key, Uint8List iv) {
    if (![16, 24, 32].contains(key.length) || iv.length != 16) {
      throw ArgumentError('AES requires a 16/24/32-byte key and 16-byte IV');
    }
    _chain = Uint8List.fromList(iv);
    _rounds = key.length ~/ 4 + 6;
    _schedule = Uint8List(16 * (_rounds + 1))..setRange(0, key.length, key);
    var rc = 1;
    final word = List<int>.filled(4, 0);
    for (var offset = key.length; offset < _schedule.length; offset += 4) {
      for (var j = 0; j < 4; j++) {
        word[j] = _schedule[offset - 4 + j];
      }
      if (offset % key.length == 0) {
        final first = word[0];
        word[0] = _s[word[1]] ^ rc;
        word[1] = _s[word[2]];
        word[2] = _s[word[3]];
        word[3] = _s[first];
        rc = _multiply(rc, 2);
      } else if (key.length == 32 && offset % key.length == 16) {
        for (var j = 0; j < 4; j++) {
          word[j] = _s[word[j]];
        }
      }
      for (var j = 0; j < 4; j++) {
        _schedule[offset + j] = _schedule[offset - key.length + j] ^ word[j];
      }
    }
  }

  void processBlock(
      Uint8List input, int offset, Uint8List output, int outputOffset) {
    final state = Uint8List(16);
    final scratch = Uint8List(16);
    final original = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      state[i] = input[offset + i];
      original[i] = state[i];
    }

    if (encrypt) {
      for (var i = 0; i < 16; i++) {
        state[i] ^= _chain[i];
      }
      _addKey(state, 0);
      for (var round = 1; round <= _rounds; round++) {
        for (var i = 0; i < 16; i++) {
          state[i] = _s[state[i]];
        }
        _shiftRows(state, scratch, false);
        if (round != _rounds) _mixColumns(state, false);
        _addKey(state, round);
      }
      for (var i = 0; i < 16; i++) {
        output[outputOffset + i] = state[i];
        _chain[i] = state[i];
      }
    } else {
      _addKey(state, _rounds);
      for (var round = _rounds - 1; round >= 0; round--) {
        _shiftRows(state, scratch, true);
        for (var i = 0; i < 16; i++) {
          state[i] = _inverse[state[i]];
        }
        _addKey(state, round);
        if (round != 0) _mixColumns(state, true);
      }
      for (var i = 0; i < 16; i++) {
        output[outputOffset + i] = state[i] ^ _chain[i];
        _chain[i] = original[i];
      }
    }
  }

  void _addKey(Uint8List state, int round) {
    final base = 16 * round;
    for (var i = 0; i < 16; i++) {
      state[i] ^= _schedule[base + i];
    }
  }

  static void _shiftRows(Uint8List state, Uint8List scratch, bool inverse) {
    scratch.setRange(0, 16, state);
    for (var r = 1; r < 4; r++) {
      final shift = inverse ? 4 - r : r;
      for (var c = 0; c < 4; c++) {
        state[4 * c + r] = scratch[4 * ((c + shift) % 4) + r];
      }
    }
  }

  static void _mixColumns(Uint8List state, bool inverse) {
    for (var c = 0; c < 4; c++) {
      final base = 4 * c;
      final a0 = state[base];
      final a1 = state[base + 1];
      final a2 = state[base + 2];
      final a3 = state[base + 3];
      if (inverse) {
        state[base] = _mul14[a0] ^ _mul11[a1] ^ _mul13[a2] ^ _mul9[a3];
        state[base + 1] = _mul9[a0] ^ _mul14[a1] ^ _mul11[a2] ^ _mul13[a3];
        state[base + 2] = _mul13[a0] ^ _mul9[a1] ^ _mul14[a2] ^ _mul11[a3];
        state[base + 3] = _mul11[a0] ^ _mul13[a1] ^ _mul9[a2] ^ _mul14[a3];
      } else {
        state[base] = _mul2[a0] ^ _mul3[a1] ^ a2 ^ a3;
        state[base + 1] = a0 ^ _mul2[a1] ^ _mul3[a2] ^ a3;
        state[base + 2] = a0 ^ a1 ^ _mul2[a2] ^ _mul3[a3];
        state[base + 3] = _mul3[a0] ^ a1 ^ a2 ^ _mul2[a3];
      }
    }
  }
}
