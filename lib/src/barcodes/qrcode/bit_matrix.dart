import 'dart:typed_data';

import 'bit_array.dart';

/// Represents a 2D matrix of bits.
class BitMatrix {
  final int _width;
  final int _height;
  late int _rowSize;
  late Int32List _bits;

  /// Create a BitMatrix.
  ///
  /// [width] - width of the matrix
  /// [height] - height of the matrix (optional, defaults to width if not provided or if using single argument constructor style)
  BitMatrix(this._width, [int? height]) : _height = height ?? _width {
    if (_width < 1 || _height < 1) {
      throw ArgumentError("Both dimensions must be greater than 0");
    }
    _rowSize = _width >> 5;
    if ((_width & 0x1f) != 0) {
      _rowSize++;
    }
    _bits = Int32List(_rowSize * _height);
  }

  /// Gets the requested bit, where true means black.
  ///
  /// [x] - The horizontal component (i.e. which column)
  /// [y] - The vertical component (i.e. which row)
  /// Returns value of given bit in matrix
  bool get(int x, int y) {
    int offset = y * _rowSize + (x >> 5);
    return ((_bits[offset] >> (x & 0x1f)) & 1) != 0;
  }

  /// Sets the given bit to true.
  ///
  /// [x] - The horizontal component (i.e. which column)
  /// [y] - The vertical component (i.e. which row)
  void set(int x, int y) {
    int offset = y * _rowSize + (x >> 5);
    _bits[offset] |= 1 << (x & 0x1f);
  }

  /// Flips the given bit.
  ///
  /// [x] - The horizontal component (i.e. which column)
  /// [y] - The vertical component (i.e. which row)
  void flip(int x, int y) {
    int offset = y * _rowSize + (x >> 5);
    _bits[offset] ^= 1 << (x & 0x1f);
  }

  /// Clears all bits (sets to false).
  void clear() {
    int max = _bits.length;
    for (int i = 0; i < max; i++) {
      _bits[i] = 0;
    }
  }

  /// Sets a square region of the bit matrix to true.
  ///
  /// [left] - The horizontal position to begin at (inclusive)
  /// [top] - The vertical position to begin at (inclusive)
  /// [width] - The width of the region
  /// [height] - The height of the region
  void setRegion(int left, int top, int width, int height) {
    if (top < 0 || left < 0) {
      throw ArgumentError("Left and top must be nonnegative");
    }
    if (height < 1 || width < 1) {
      throw ArgumentError("Height and width must be at least 1");
    }
    int right = left + width;
    int bottom = top + height;
    if (bottom > _height || right > _width) {
      throw ArgumentError("The region must fit inside the matrix");
    }
    for (int y = top; y < bottom; y++) {
      int offset = y * _rowSize;
      for (int x = left; x < right; x++) {
        _bits[offset + (x >> 5)] |= 1 << (x & 0x1f);
      }
    }
  }

  /// A fast method to retrieve one row of data from the matrix as a BitArray.
  ///
  /// [y] - The row to retrieve
  /// [row] - An optional caller-allocated BitArray, will be allocated if null or too small
  /// Returns The resulting BitArray
  BitArray getRow(int y, [BitArray? row]) {
    if (row == null || row.getSize() < _width) {
      row = BitArray(_width);
    }
    int offset = y * _rowSize;
    for (int x = 0; x < _rowSize; x++) {
      row.setBulk(x << 5, _bits[offset + x]);
    }
    return row;
  }

  /// Returns The width of the matrix
  int getWidth() {
    return _width;
  }

  /// Returns The height of the matrix
  int getHeight() {
    return _height;
  }

  /// This method is for compatibility with older code.
  ///
  /// Returns row/column dimension of this matrix
  int getDimension() {
    if (_width != _height) {
      throw Exception("Can't call getDimension() on a non-square matrix");
    }
    return _width;
  }

  @override
  String toString() {
    StringBuffer result = StringBuffer();
    for (int y = 0; y < _height; y++) {
      for (int x = 0; x < _width; x++) {
        result.write(get(x, y) ? "X " : "  ");
      }
      result.write('\n');
    }
    return result.toString();
  }
}
