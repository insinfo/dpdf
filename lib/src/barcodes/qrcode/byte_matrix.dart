import 'dart:typed_data';

/// A class which wraps a 2D array of bytes.
class ByteMatrix {
  late List<Uint8List> _bytes;
  final int _width;
  final int _height;

  /// Create a ByteMatix of given width and height, with the values initialized to 0
  ///
  /// [width] - width of the matrix
  /// [height] - height of the matrix
  ByteMatrix(this._width, this._height) {
    _bytes = List.generate(_height, (i) => Uint8List(_width));
  }

  /// Returns height of the matrix
  int getHeight() {
    return _height;
  }

  /// Returns width of the matrix
  int getWidth() {
    return _width;
  }

  /// Get the value of the byte at (x,y)
  ///
  /// [x] - the width coordinate
  /// [y] - the height coordinate
  /// Returns the byte value at position (x,y)
  int get(int x, int y) {
    return _bytes[y][x];
  }

  /// Returns matrix as byte[][]
  List<Uint8List> getArray() {
    return _bytes;
  }

  /// Set the value of the byte at (x,y)
  ///
  /// [x] - the width coordinate
  /// [y] - the height coordinate
  /// [value] - the new byte value
  void set(int x, int y, int value) {
    _bytes[y][x] = value;
  }

  /// Resets the contents of the entire matrix to value
  ///
  /// [value] - new value of every element
  void clear(int value) {
    for (int y = 0; y < _height; ++y) {
      for (int x = 0; x < _width; ++x) {
        _bytes[y][x] = value;
      }
    }
  }

  /// Returns String representation
  @override
  String toString() {
    StringBuffer result = StringBuffer();
    for (int y = 0; y < _height; ++y) {
      for (int x = 0; x < _width; ++x) {
        switch (_bytes[y][x]) {
          case 0:
            {
              result.write(" 0");
              break;
            }

          case 1:
            {
              result.write(" 1");
              break;
            }

          default:
            {
              result.write("  ");
              break;
            }
        }
      }
      result.write('\n');
    }
    return result.toString();
  }
}
