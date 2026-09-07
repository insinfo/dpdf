import 'dart:typed_data';
import 'bit_array.dart';

/// Rectangular binary raster, stored as independent byte rows.
class CraftBitMatrix {
  final int _width;
  final int _height;
  late final List<Uint8List> _rows;

  CraftBitMatrix(this._width, [int? height]) : _height = height ?? _width {
    if (_width <= 0 || _height <= 0) {
      throw ArgumentError(
          'Raster dimensions must be positive: $_width x $_height');
    }
    _rows = List.generate(_height, (_) => Uint8List(_width));
  }

  void _check(int x, int y) {
    RangeError.checkValidIndex(y, _rows, 'y');
    RangeError.checkValidIndex(x, _rows[y], 'x');
  }

  bool get(int x, int y) {
    _check(x, y);
    return _rows[y][x] != 0;
  }

  void set(int x, int y) {
    _check(x, y);
    _rows[y][x] = 1;
  }

  void flip(int x, int y) {
    _check(x, y);
    _rows[y][x] ^= 1;
  }

  void clear() {
    for (final row in _rows) {
      row.fillRange(0, _width, 0);
    }
  }

  void setRegion(int left, int top, int width, int height) {
    if (left < 0 ||
        top < 0 ||
        width <= 0 ||
        height <= 0 ||
        width > _width - left ||
        height > _height - top) {
      throw ArgumentError('Region must have positive extent within the raster');
    }
    for (final row in _rows.getRange(top, top + height)) {
      row.fillRange(left, left + width, 1);
    }
  }

  CraftBitArray getRow(int y, [CraftBitArray? row]) {
    RangeError.checkValidIndex(y, _rows, 'y');
    final result =
        row != null && row.getSize() >= _width ? row : CraftBitArray(_width);
    // Only replace words belonging to this matrix; a larger caller buffer keeps
    // its subsequent words, matching the original public behavior.
    for (var base = 0; base < _width; base += 32) {
      var packed = 0;
      final end = base + 32 < _width ? base + 32 : _width;
      for (var x = base; x < end; x++) {
        packed |= _rows[y][x] << (x - base);
      }
      result.setBulk(base, packed);
    }
    return result;
  }

  int getWidth() => _width;
  int getHeight() => _height;
  int getDimension() {
    if (_width != _height) {
      throw StateError('A rectangular raster has no single dimension');
    }
    return _width;
  }

  @override
  String toString() => _rows
      .map((row) => '${row.map((cell) => cell == 0 ? '  ' : 'X ').join()}\n')
      .join();
}
