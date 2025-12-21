import 'dart:typed_data';

import 'byte_utils.dart';

/// A growable byte buffer for building byte arrays.
///
/// This class is used extensively in iText for constructing PDF content
/// and tokenizing PDF data.
class ByteBuffer {
  /// Hex digit bytes: 0-9, a-f.
  static final Uint8List _hexBytes = Uint8List.fromList([
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, // 0-9
    97, 98, 99, 100, 101, 102, // a-f
  ]);

  /// Internal buffer.
  Uint8List _buffer;

  /// Current size (number of valid bytes).
  int _count = 0;

  /// Creates a ByteBuffer with default capacity (128).
  ByteBuffer() : this.withCapacity(128);

  /// Creates a ByteBuffer with specified initial capacity.
  ByteBuffer.withCapacity(int size)
      : _buffer = Uint8List(size < 1 ? 128 : size);

  /// Converts a hex character to its numeric value.
  ///
  /// Returns -1 if the character is not a valid hex digit.
  static int getHex(int v) {
    if (v >= 0x30 && v <= 0x39) {
      // '0' - '9'
      return v - 0x30;
    }
    if (v >= 0x41 && v <= 0x46) {
      // 'A' - 'F'
      return v - 0x41 + 10;
    }
    if (v >= 0x61 && v <= 0x66) {
      // 'a' - 'f'
      return v - 0x61 + 10;
    }
    return -1;
  }

  /// Appends a single byte to the buffer.
  ByteBuffer append(int b) {
    final newCount = _count + 1;
    _ensureCapacity(newCount);
    _buffer[_count] = b & 0xFF;
    _count = newCount;
    return this;
  }

  /// Appends bytes from a list with offset and length.
  ByteBuffer appendRange(List<int> b, int off, int len) {
    if (off < 0 ||
        off > b.length ||
        len < 0 ||
        (off + len) > b.length ||
        len == 0) {
      return this;
    }
    final newCount = _count + len;
    _ensureCapacity(newCount);
    for (var i = 0; i < len; i++) {
      _buffer[_count + i] = b[off + i] & 0xFF;
    }
    _count = newCount;
    return this;
  }

  /// Appends all bytes from a list.
  ByteBuffer appendBytes(List<int> b) {
    return appendRange(b, 0, b.length);
  }

  /// Appends a string as ISO-8859-1 bytes.
  ByteBuffer appendString(String str) {
    return appendBytes(ByteUtils.getIsoBytes(str));
  }

  /// Appends a byte as two hex digits.
  ByteBuffer appendHex(int b) {
    append(_hexBytes[(b >> 4) & 0x0f]);
    return append(_hexBytes[b & 0x0f]);
  }

  /// Gets the byte at the specified index.
  int get(int index) {
    if (index >= _count) {
      throw RangeError('Index: $index, Size: $_count');
    }
    return _buffer[index];
  }

  /// Gets the internal buffer.
  ///
  /// Note: The buffer may be larger than [size]. Only bytes from 0 to
  /// [size] - 1 are valid.
  Uint8List getInternalBuffer() => _buffer;

  /// Returns the number of valid bytes in the buffer.
  int size() => _count;

  /// Returns true if the buffer is empty.
  bool isEmpty() => _count == 0;

  /// Returns the current capacity of the buffer.
  int capacity() => _buffer.length;

  /// Resets the buffer, setting size to 0.
  ByteBuffer reset() {
    _count = 0;
    return this;
  }

  /// Creates a copy of bytes from offset with given length.
  Uint8List toByteArrayRange(int off, int len) {
    final newBuf = Uint8List(len);
    for (var i = 0; i < len; i++) {
      newBuf[i] = _buffer[off + i];
    }
    return newBuf;
  }

  /// Creates a copy of all valid bytes.
  Uint8List toByteArray() {
    return toByteArrayRange(0, _count);
  }

  /// Checks if the buffer starts with the given bytes.
  bool startsWith(List<int> b) {
    if (size() < b.length) {
      return false;
    }
    for (var k = 0; k < b.length; k++) {
      if (_buffer[k] != b[k]) {
        return false;
      }
    }
    return true;
  }

  /// Fills the ByteBuffer from the end.
  ///
  /// Sets byte at `capacity() - size() - 1` position.
  /// This is an internal method used for number formatting.
  ByteBuffer prepend(int b) {
    _buffer[_buffer.length - _count - 1] = b & 0xFF;
    _count++;
    return this;
  }

  /// Fills the ByteBuffer from the end with multiple bytes.
  ///
  /// Sets bytes from `capacity() - size() - b.length` position.
  /// This is an internal method used for number formatting.
  ByteBuffer prependBytes(List<int> b) {
    final start = _buffer.length - _count - b.length;
    for (var i = 0; i < b.length; i++) {
      _buffer[start + i] = b[i] & 0xFF;
    }
    _count += b.length;
    return this;
  }

  /// Ensures the buffer has at least the specified capacity.
  void _ensureCapacity(int minCapacity) {
    if (minCapacity > _buffer.length) {
      final newSize =
          _buffer.length << 1 > minCapacity ? _buffer.length << 1 : minCapacity;
      final newBuffer = Uint8List(newSize);
      for (var i = 0; i < _count; i++) {
        newBuffer[i] = _buffer[i];
      }
      _buffer = newBuffer;
    }
  }
}
