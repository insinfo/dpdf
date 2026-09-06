import 'dart:typed_data';
import 'dart:math' as math;

/// This class implements an array of unsigned bytes.
class ByteArray {
  static const int INITIAL_SIZE = 32;

  Uint8List? _bytes;
  int _size = 0;

  /// Creates a new ByteArray instance.
  ///
  /// [arg] can be int (size) or Uint8List (bytes) or List<int>.
  ByteArray([dynamic arg]) {
    if (arg == null) {
      _bytes = null;
      _size = 0;
    } else if (arg is int) {
      _bytes = Uint8List(arg);
      _size = arg;
    } else if (arg is Uint8List) {
      _bytes = arg;
      _size = arg.length;
    } else if (arg is List<int>) {
      _bytes = Uint8List.fromList(arg);
      _size = arg.length;
    }
  }

  /// Access an unsigned byte at location index.
  ///
  /// [index] - The index in the array to access.
  /// Returns The unsigned value of the byte as an int.
  int at(int index) {
    return _bytes![index] & 0xff;
  }

  /// Set the value at "index" to "value"
  ///
  /// [index] - position in the byte-array
  /// [value] - new value
  void set(int index, int value) {
    _bytes![index] = value;
  }

  /// Returns size of the array
  int size() {
    return _size;
  }

  /// Returns true if size is equal to 0, false otherwise
  bool isEmpty() {
    return _size == 0;
  }

  /// Append a byte to the end of the array.
  ///
  /// Append a byte to the end of the array. If the array is too small, it's capacity is doubled.
  /// [value] - byte to append.
  void appendByte(int value) {
    if (_size == 0 || _size >= _bytes!.length) {
      int newSize = math.max(INITIAL_SIZE, _size << 1);
      reserve(newSize);
    }
    _bytes![_size] = value;
    _size++;
  }

  /// Increase the capacity of the array to "capacity" if the current capacity is smaller
  ///
  /// [capacity] - the new capacity
  void reserve(int capacity) {
    if (_bytes == null || _bytes!.length < capacity) {
      Uint8List newArray = Uint8List(capacity);
      if (_bytes != null) {
        newArray.setRange(0, _bytes!.length, _bytes!);
      }
      _bytes = newArray;
    }
  }

  /// Copy count bytes from array source starting at offset.
  ///
  /// [source] - source of the copied bytes
  /// [offset] - offset to start at
  /// [count] - number of bytes to copy
  void setBytes(List<int> source, int offset, int count) {
    _bytes = Uint8List(count);
    _size = count;
    for (int x = 0; x < count; x++) {
      _bytes![x] = source[offset + x];
    }
  }

  /// Map setRange to underlying Uint8List
  void setRange(List<int> source, int offset, int count) {
    if (_bytes == null || _bytes!.length < count) {
      _bytes = Uint8List(count);
    }
    for (int i = 0; i < count; i++) {
      _bytes![i] = source[offset + i];
    }
    _size = count;
  }

  /// Copies count bytes from source starting at offset to this array.
  /// This behaves like C# Set(source, offset, count).
  void setWithOffset(List<int> source, int offset, int count) {
    if (_size < count) {
      // Should throw or resize?
    }
    for (int i = 0; i < count; i++) {
      _bytes![i] = source[offset + i];
    }
  }
}
