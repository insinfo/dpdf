import 'dart:typed_data';

/// AES round transformations from FIPS 197, with a CBC chaining state.
class AesCbcCore {
  final bool encrypt;
  late final List<int> _schedule;
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
      for (var i = 0; i < 254; i++) inverse = _multiply(inverse, x);
    }
    var value = inverse ^ 0x63;
    for (var i = 1; i <= 4; i++) {
      value ^= ((inverse << i) | (inverse >> (8 - i))) & 255;
    }
    return value;
  }

  static final _s = List<int>.generate(256, _substitute);
  static final _inverse = List<int>.generate(256, (i) => _s.indexOf(i));
  AesCbcCore(this.encrypt, Uint8List key, Uint8List iv) {
    if (![16, 24, 32].contains(key.length) || iv.length != 16) {
      throw ArgumentError('AES requires a 16/24/32-byte key and 16-byte IV');
    }
    _chain = Uint8List.fromList(iv);
    _rounds = key.length ~/ 4 + 6;
    _schedule = List<int>.filled(16 * (_rounds + 1), 0)
      ..setRange(0, key.length, key);
    var rc = 1;
    for (var offset = key.length; offset < _schedule.length; offset += 4) {
      var word = _schedule.sublist(offset - 4, offset);
      if (offset % key.length == 0) {
        word = [_s[word[1]] ^ rc, _s[word[2]], _s[word[3]], _s[word[0]]];
        rc = _multiply(rc, 2);
      } else if (key.length == 32 && offset % key.length == 16) {
        word = word.map((v) => _s[v]).toList();
      }
      for (var j = 0; j < 4; j++)
        _schedule[offset + j] = _schedule[offset - key.length + j] ^ word[j];
    }
  }
  void processBlock(
      Uint8List input, int offset, Uint8List output, int outputOffset) {
    final original = Uint8List.fromList(input.sublist(offset, offset + 16));
    var state = List<int>.from(original);
    void addKey(int round) {
      for (var i = 0; i < 16; i++) state[i] ^= _schedule[16 * round + i];
    }

    void shift(bool inverse) {
      final copy = List<int>.from(state);
      for (var r = 0; r < 4; r++)
        for (var c = 0; c < 4; c++) {
          state[4 * c + r] = copy[4 * ((c + (inverse ? 4 - r : r)) % 4) + r];
        }
    }

    void mix(bool inverse) {
      final matrix = inverse ? [14, 11, 13, 9] : [2, 3, 1, 1];
      for (var c = 0; c < 4; c++) {
        final col = state.sublist(4 * c, 4 * c + 4);
        for (var r = 0; r < 4; r++) {
          var value = 0;
          for (var k = 0; k < 4; k++)
            value ^= _multiply(col[k], matrix[(k - r + 4) % 4]);
          state[4 * c + r] = value;
        }
      }
    }

    if (encrypt) {
      for (var i = 0; i < 16; i++) state[i] ^= _chain[i];
      addKey(0);
      for (var round = 1; round <= _rounds; round++) {
        state = state.map((v) => _s[v]).toList();
        shift(false);
        if (round != _rounds) mix(false);
        addKey(round);
      }
    } else {
      addKey(_rounds);
      for (var round = _rounds - 1; round >= 0; round--) {
        shift(true);
        state = state.map((v) => _inverse[v]).toList();
        addKey(round);
        if (round != 0) mix(true);
      }
      for (var i = 0; i < 16; i++) state[i] ^= _chain[i];
    }
    output.setRange(outputOffset, outputOffset + 16, state);
    _chain = encrypt ? Uint8List.fromList(state) : original;
  }
}
