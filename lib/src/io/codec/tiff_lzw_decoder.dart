import 'dart:typed_data';
import '../exceptions/io_exception.dart';

/// LZW decoder for TIFF images.
///
/// This class performs LZW decompression for TIFF image data.
/// Based on Sun Microsystems' TIFFLZWDecompressor.
class TIFFLZWDecoder {
  List<Uint8List?> _stringTable = List.filled(4096, null);
  Uint8List? _data;
  late Uint8List _uncompData;
  int _tableIndex = 0;
  int _bitsToGet = 9;
  int _bytePointer = 0;
  int _dstIndex = 0;
  int _nextData = 0;
  int _nextBits = 0;

  final int _w;

  final int _predictor;
  final int _samplesPerPixel;

  static const List<int> _andTable = [511, 1023, 2047, 4095];

  /// Creates a TIFF LZW decoder.
  ///
  /// [w] - Image width
  /// [predictor] - Predictor mode (2 for horizontal differencing)
  /// [samplesPerPixel] - Number of samples per pixel
  TIFFLZWDecoder(this._w, this._predictor, this._samplesPerPixel);

  /// Decodes LZW compressed data.
  ///
  /// [data] - The compressed data
  /// [uncompData] - Array to receive uncompressed data
  /// [h] - Number of rows the compressed data contains
  ///
  /// Returns the decoded data.
  Uint8List decode(Uint8List data, Uint8List uncompData, int h) {
    if (data.length >= 2 && data[0] == 0x00 && data[1] == 0x01) {
      throw IoException('TIFF 5.0-style LZW codes are not supported');
    }

    _initializeStringTable();
    _data = data;
    _uncompData = uncompData;

    // Initialize pointers
    _bytePointer = 0;
    _dstIndex = 0;
    _nextData = 0;
    _nextBits = 0;

    int code;
    int oldCode = 0;
    Uint8List? str;

    while ((code = _getNextCode()) != 257 && _dstIndex < uncompData.length) {
      if (code == 256) {
        _initializeStringTable();
        code = _getNextCode();
        if (code == 257) {
          break;
        }
        _writeString(_stringTable[code]!);
        oldCode = code;
      } else {
        if (code < _tableIndex) {
          str = _stringTable[code];
          _writeString(str!);
          _addStringToTableWithByte(_stringTable[oldCode]!, str[0]);
          oldCode = code;
        } else {
          str = _stringTable[oldCode];
          str = _composeString(str!, str[0]);
          _writeString(str);
          _addStringToTable(str);
          oldCode = code;
        }
      }
    }

    // Horizontal Differencing Predictor
    if (_predictor == 2) {
      for (int j = 0; j < h; j++) {
        int count = _samplesPerPixel * (j * _w + 1);
        for (int i = _samplesPerPixel; i < _w * _samplesPerPixel; i++) {
          uncompData[count] =
              (uncompData[count] + uncompData[count - _samplesPerPixel]) & 0xFF;
          count++;
        }
      }
    }

    return uncompData;
  }

  /// Initialize the string table.
  void _initializeStringTable() {
    _stringTable = List.filled(4096, null);
    for (int i = 0; i < 256; i++) {
      _stringTable[i] = Uint8List.fromList([i]);
    }
    _tableIndex = 258;
    _bitsToGet = 9;
  }

  /// Write out the string just uncompressed.
  void _writeString(Uint8List str) {
    int max = _uncompData.length - _dstIndex;
    if (str.length < max) {
      max = str.length;
    }
    _uncompData.setRange(_dstIndex, _dstIndex + max, str);
    _dstIndex += max;
  }

  /// Add a new string to the string table.
  void _addStringToTableWithByte(Uint8List oldString, int newByte) {
    final length = oldString.length;
    final str = Uint8List(length + 1);
    str.setRange(0, length, oldString);
    str[length] = newByte;

    _stringTable[_tableIndex++] = str;
    _updateBitsToGet();
  }

  /// Add a new string to the string table.
  void _addStringToTable(Uint8List str) {
    _stringTable[_tableIndex++] = str;
    _updateBitsToGet();
  }

  void _updateBitsToGet() {
    if (_tableIndex == 511) {
      _bitsToGet = 10;
    } else if (_tableIndex == 1023) {
      _bitsToGet = 11;
    } else if (_tableIndex == 2047) {
      _bitsToGet = 12;
    }
  }

  /// Append newByte to the end of oldString.
  Uint8List _composeString(Uint8List oldString, int newByte) {
    final length = oldString.length;
    final str = Uint8List(length + 1);
    str.setRange(0, length, oldString);
    str[length] = newByte;
    return str;
  }

  /// Returns the next 9, 10, 11 or 12 bits.
  int _getNextCode() {
    try {
      _nextData = (_nextData << 8) | (_data![_bytePointer++] & 0xff);
      _nextBits += 8;

      if (_nextBits < _bitsToGet) {
        _nextData = (_nextData << 8) | (_data![_bytePointer++] & 0xff);
        _nextBits += 8;
      }

      int code =
          (_nextData >> (_nextBits - _bitsToGet)) & _andTable[_bitsToGet - 9];
      _nextBits -= _bitsToGet;
      return code;
    } on RangeError {
      // Strip not terminated as expected: return EndOfInformation code.
      return 257;
    }
  }
}

/// Utility class for LZW decoding.
class LZWDecoder {
  LZWDecoder._();

  /// Decodes LZW compressed data.
  ///
  /// [data] - Compressed input data
  /// [expectedSize] - Expected size of uncompressed output
  /// [width] - Image width (for predictor)
  /// [predictor] - Predictor mode (1 = none, 2 = horizontal differencing)
  /// [samplesPerPixel] - Number of samples per pixel
  /// [height] - Image height
  ///
  /// Returns decompressed data.
  static Uint8List decode(
    Uint8List data, {
    required int expectedSize,
    int width = 0,
    int predictor = 1,
    int samplesPerPixel = 1,
    int height = 1,
  }) {
    final uncompData = Uint8List(expectedSize);
    final decoder = TIFFLZWDecoder(width, predictor, samplesPerPixel);
    return decoder.decode(data, uncompData, height);
  }
}
