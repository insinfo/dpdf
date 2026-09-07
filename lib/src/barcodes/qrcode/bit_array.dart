import 'dart:typed_data';

/// Fixed-length bits. The exposed words use bit zero as their low bit.
class BitArray {
  final int _size;
  late Int32List _words;

  BitArray(this._size) {
    if (_size <= 0) {
      throw ArgumentError.value(_size, 'size', 'Expected a positive bit count');
    }
    _words = Int32List((_size + 31) ~/ 32);
  }

  int getSize() => _size;

  void _check(int index) =>
      RangeError.checkValidIndex(index, this, 'index', _size);

  bool get(int i) {
    _check(i);
    return (_words[i ~/ 32] & (1 << (i % 32))) != 0;
  }

  void set(int i) {
    _check(i);
    _words[i ~/ 32] |= 1 << (i % 32);
  }

  void flip(int i) {
    _check(i);
    _words[i ~/ 32] ^= 1 << (i % 32);
  }

  /// Replaces the storage word containing [i], retaining the legacy contract.
  void setBulk(int i, int newBits) {
    _check(i);
    _words[i ~/ 32] = newBits;
  }

  void clear() => _words.fillRange(0, _words.length, 0);

  bool isRange(int start, int end, bool value) {
    RangeError.checkValidRange(start, end, _size);
    for (var cursor = start; cursor < end; cursor++) {
      if (get(cursor) != value) return false;
    }
    return true;
  }

  /// Mutable storage retained for callers that exchange packed 32-bit words.
  Int32List getBitArray() => _words;

  void reverse() {
    // Keep a distinct result so references previously returned remain snapshots
    // of the old storage, as required by the existing API.
    final previous = _words;
    _words = Int32List(previous.length);
    for (var source = 0; source < _size; source++) {
      if ((previous[source ~/ 32] & (1 << (source % 32))) != 0) {
        set(_size - source - 1);
      }
    }
  }

  @override
  String toString() => List.generate((_size + 7) ~/ 8, (group) {
        final end = (group + 1) * 8 < _size ? (group + 1) * 8 : _size;
        return ' ${List.generate(end - group * 8, (offset) => get(group * 8 + offset) ? 'X' : '.').join()}';
      }).join();
}
