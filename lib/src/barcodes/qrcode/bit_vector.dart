import 'dart:typed_data';

/// Append-only bit sequence, serialized most-significant bit first per byte.
class BitVector {
  int _length = 0;
  Uint8List _storage = Uint8List(32);

  int size() => _length;
  int sizeInBytes() => (_length + 7) ~/ 8;

  int at(int index) {
    RangeError.checkValidIndex(index, this, 'index', _length);
    return (_storage[index ~/ 8] >> (7 - index % 8)) & 1;
  }

  void _reserve(int totalBits) {
    final needed = (totalBits + 7) ~/ 8;
    if (needed <= _storage.length) return;
    final capacity = ((needed + 255) ~/ 256) * 256;
    _storage = Uint8List(capacity)..setRange(0, _storage.length, _storage);
  }

  void appendBit(int bit) {
    if (bit != 0 && bit != 1) {
      throw ArgumentError.value(bit, 'bit', 'Expected binary digit');
    }
    _reserve(_length + 1);
    final byte = _length ~/ 8;
    final shift = 7 - _length % 8;
    if (shift == 7) _storage[byte] = 0;
    _storage[byte] = (_storage[byte] & ~(1 << shift)) | (bit << shift);
    _length++;
  }

  /// Appends the low [numBits] bits of [value], highest selected bit first.
  void appendBits(int value, int numBits) {
    if (numBits < 0 || numBits > 32) {
      throw ArgumentError.value(
          numBits, 'numBits', 'Expected a count from 0 through 32');
    }
    _reserve(_length + numBits);
    for (var shift = numBits; shift > 0;) {
      appendBit((value >> --shift) & 1);
    }
  }

  void appendBitVector(BitVector bits) {
    final count = bits.size();
    _reserve(_length + count);
    for (var index = 0; index < count; index++) {
      appendBit(bits.at(index));
    }
  }

  void xor(BitVector other) {
    if (other.size() != _length) {
      throw ArgumentError('XOR requires equal bit counts');
    }
    for (var byte = 0; byte < sizeInBytes(); byte++) {
      _storage[byte] ^= other._storage[byte];
    }
  }

  /// Mutable byte storage; capacity may exceed the serialized byte count.
  Uint8List getArray() => _storage;

  @override
  String toString() => List.generate(_length, at).join();
}
