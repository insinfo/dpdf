import 'dart:typed_data';

/// A simple, fast array of bits, represented compactly by an array of ints internally.
class BitArray {
  late Int32List _bits;
  final int _size;

  BitArray(this._size) {
    if (_size < 1) {
      throw ArgumentError("size must be at least 1");
    }
    _bits = _makeArray(_size);
  }

  int getSize() {
    return _size;
  }

  /// [i] - bit to get.
  /// Returns true iff bit i is set
  bool get(int i) {
    return (_bits[i >> 5] & (1 << (i & 0x1F))) != 0;
  }

  /// Sets bit i.
  ///
  /// [i] - bit to set
  void set(int i) {
    _bits[i >> 5] |= 1 << (i & 0x1F);
  }

  /// Flips bit i.
  ///
  /// [i] - bit to set
  void flip(int i) {
    _bits[i >> 5] ^= 1 << (i & 0x1F);
  }

  /// Sets a block of 32 bits, starting at bit i.
  ///
  /// [i] - first bit to set
  /// [newBits] - the new value of the next 32 bits. Note again that the least-significant bit
  /// corresponds to bit i, the next-least-significant to i+1, and so on.
  void setBulk(int i, int newBits) {
    _bits[i >> 5] = newBits;
  }

  /// Clears all bits (sets to false).
  void clear() {
    int max = _bits.length;
    for (int i = 0; i < max; i++) {
      _bits[i] = 0;
    }
  }

  /// Efficient method to check if a range of bits is set, or not set.
  ///
  /// [start] - start of range, inclusive.
  /// [end] - end of range, exclusive
  /// [value] - if true, checks that bits in range are set, otherwise checks that they are not set
  /// Returns true iff all bits are set or not set in range, according to value argument
  bool isRange(int start, int end, bool value) {
    if (end < start) {
      throw ArgumentError();
    }
    if (end == start) {
      // empty range matches
      return true;
    }
    // will be easier to treat this as the last actually set bit -- inclusive
    end--;
    int firstInt = start >> 5;
    int lastInt = end >> 5;
    for (int i = firstInt; i <= lastInt; i++) {
      int firstBit = i > firstInt ? 0 : start & 0x1F;
      int lastBit = i < lastInt ? 31 : end & 0x1F;
      int mask;
      if (firstBit == 0 && lastBit == 31) {
        mask = -1;
      } else {
        mask = 0;
        for (int j = firstBit; j <= lastBit; j++) {
          mask |= 1 << j;
        }
      }
      // Return false if we're looking for 1s and the masked bits[i] isn't all 1s (that is,
      // equals the mask, or we're looking for 0s and the masked portion is not all 0s
      if ((_bits[i] & mask) != (value ? mask : 0)) {
        return false;
      }
    }
    return true;
  }

  /// Returns underlying array of ints. The first element holds the first 32 bits, and the least
  /// significant bit is bit 0.
  Int32List getBitArray() {
    return _bits;
  }

  /// Reverses all bits in the array.
  void reverse() {
    Int32List newBits = Int32List(_bits.length);
    int len = _size;
    for (int i = 0; i < len; i++) {
      if (get(len - i - 1)) {
        newBits[i >> 5] |= 1 << (i & 0x1F);
      }
    }
    _bits = newBits;
  }

  static Int32List _makeArray(int size) {
    int arraySize = size >> 5;
    if ((size & 0x1F) != 0) {
      arraySize++;
    }
    return Int32List(arraySize);
  }

  @override
  String toString() {
    StringBuffer result = StringBuffer();
    for (int i = 0; i < _size; i++) {
      if ((i & 0x07) == 0) {
        result.write(' ');
      }
      result.write(get(i) ? 'X' : '.');
    }
    return result.toString();
  }
}
