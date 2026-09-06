import 'dart:typed_data';

/// JAVAPORT: This should be combined with BitArray in the future, although that class is not yet
/// dynamically resizeable.
class BitVector {
  int _sizeInBits = 0;
  late Uint8List _array;

  // For efficiency, start out with some room to work.
  static const int _DEFAULT_SIZE_IN_BYTES = 32;

  /// Create a bitvector usng the default size
  BitVector() {
    _sizeInBits = 0;
    _array = Uint8List(_DEFAULT_SIZE_IN_BYTES);
  }

  /// Return the bit value at "index".
  ///
  /// [index] - index in the vector
  /// Returns bit value at "index"
  int at(int index) {
    if (index < 0 || index >= _sizeInBits) {
      throw ArgumentError("Bad index: $index");
    }
    int value = _array[index >> 3] & 0xff;
    return (value >> (7 - (index & 0x7))) & 1;
  }

  /// Returns the number of bits in the bit vector.
  int size() {
    return _sizeInBits;
  }

  /// Returns the number of bytes in the bit vector.
  int sizeInBytes() {
    return (_sizeInBits + 7) >> 3;
  }

  /// Append the a bit to the bit vector
  ///
  /// [bit] - 0 or 1
  void appendBit(int bit) {
    if (!(bit == 0 || bit == 1)) {
      throw ArgumentError("Bad bit");
    }
    int numBitsInLastByte = _sizeInBits & 0x7;
    // We'll expand array if we don't have bits in the last byte.
    if (numBitsInLastByte == 0) {
      _appendByte(0);
      _sizeInBits -= 8;
    }
    // Modify the last byte.
    _array[_sizeInBits >> 3] |= (bit << (7 - numBitsInLastByte));
    ++_sizeInBits;
  }

  /// Append "numBits" bits in "value" to the bit vector.
  ///
  /// [value] - int interpreted as bitvector
  /// [numBits] - 0 <= numBits <= 32.
  void appendBits(int value, int numBits) {
    if (numBits < 0 || numBits > 32) {
      throw ArgumentError("Num bits must be between 0 and 32");
    }
    int numBitsLeft = numBits;
    while (numBitsLeft > 0) {
      // Optimization for byte-oriented appending.
      if ((_sizeInBits & 0x7) == 0 && numBitsLeft >= 8) {
        int newByte = (value >> (numBitsLeft - 8)) & 0xff;
        _appendByte(newByte);
        numBitsLeft -= 8;
      } else {
        int bit = (value >> (numBitsLeft - 1)) & 1;
        appendBit(bit);
        --numBitsLeft;
      }
    }
  }

  /// Append a different BitVector to this BitVector
  ///
  /// [bits] - BitVector to append
  void appendBitVector(BitVector bits) {
    int size = bits.size();
    for (int i = 0; i < size; ++i) {
      appendBit(bits.at(i));
    }
  }

  /// XOR the contents of this bitvector with the contents of "other"
  ///
  /// [other] - Bitvector of equal length
  void xor(BitVector other) {
    if (_sizeInBits != other.size()) {
      throw ArgumentError("BitVector sizes don't match");
    }
    int sizeInBytes = (_sizeInBits + 7) >> 3;
    for (int i = 0; i < sizeInBytes; ++i) {
      // The last byte could be incomplete (i.e. not have 8 bits in
      // it) but there is no problem since 0 XOR 0 == 0.
      _array[i] ^= other._array[i];
    }
  }

  @override
  String toString() {
    StringBuffer result = StringBuffer();
    for (int i = 0; i < _sizeInBits; ++i) {
      if (at(i) == 0) {
        result.write('0');
      } else {
        if (at(i) == 1) {
          result.write('1');
        } else {
          throw ArgumentError("Byte isn't 0 or 1");
        }
      }
    }
    return result.toString();
  }

  /// Callers should not assume that array.length is the exact number of bytes needed to hold
  /// sizeInBits - it will typically be larger for efficiency.
  ///
  /// Returns size of the array containing the bitvector
  Uint8List getArray() {
    return _array;
  }

  /// Add a new byte to the end, possibly reallocating and doubling the size of the array if we've
  /// run out of room.
  ///
  /// [value] - byte to add.
  void _appendByte(int value) {
    if ((_sizeInBits >> 3) == _array.length) {
      Uint8List newArray = Uint8List(_array.length << 1);
      List.copyRange(newArray, 0, _array, 0, _array.length);
      _array = newArray;
    }
    _array[_sizeInBits >> 3] = value;
    _sizeInBits += 8;
  }
}
