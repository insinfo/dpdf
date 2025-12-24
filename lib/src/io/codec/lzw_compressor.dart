import 'dart:typed_data';
import 'bit_file.dart';
import 'lzw_string_table.dart';

/// LZW Compressor for TIFF and GIF image formats.
/// TODO concluir e otimizar
/// Modified from original LZWCompressor to accept a buffer of data
/// to be compressed rather than a stream.
class LZWCompressor {
  /// Base underlying code size of data being compressed (8 for TIFF, 1-8 for GIF)
  final int _codeSize;

  /// Reserved clear code based on code size
  final int _clearCode;

  /// Reserved end of data code based on code size
  final int _endOfInfo;

  /// Current number of bits output for each code
  int _numBits;

  /// Limit at which current number of bits code size has to be increased
  int _limit;

  /// Prefix code representing predecessor string to current input point
  int _prefix;

  /// Output destination for bit codes
  final BitFile _bf;

  /// General purpose LZW string table
  final LZWStringTable _lzss;

  /// Modify the limits of code values due to TIFF bug/feature
  final bool _tiffFudge;

  /// Creates an LZW compressor.
  ///
  /// [output] - Destination BytesBuilder for compressed data
  /// [codeSize] - Initial code size for LZW compressor
  /// [tiff] - Flag indicating TIFF LZW fudge needs to be applied
  LZWCompressor(BytesBuilder output, int codeSize, bool tiff)
      : _codeSize = codeSize,
        _tiffFudge = tiff,
        _clearCode = 1 << codeSize,
        _endOfInfo = (1 << codeSize) + 1,
        _numBits = codeSize + 1,
        _limit = (1 << (codeSize + 1)) - 1 - (tiff ? 1 : 0),
        _prefix = -1,
        _lzss = LZWStringTable(),
        _bf = BitFile(output, !tiff) {
    _lzss.clearTable(codeSize);
    _bf.writeBits(_clearCode, _numBits);
  }

  /// Compresses data from the buffer.
  ///
  /// [buf] - The data to be compressed
  /// [offset] - The offset at which data starts
  /// [length] - The length of data being compressed
  void compress(Uint8List buf, int offset, int length) {
    int maxOffset = offset + length;

    for (int idx = offset; idx < maxOffset; ++idx) {
      int c = buf[idx];
      int index = _lzss.findCharString(_prefix, c);

      if (index != -1) {
        _prefix = index;
      } else {
        _bf.writeBits(_prefix, _numBits);

        if (_lzss.addCharString(_prefix, c) > _limit) {
          if (_numBits == 12) {
            _bf.writeBits(_clearCode, _numBits);
            _lzss.clearTable(_codeSize);
            _numBits = _codeSize + 1;
          } else {
            ++_numBits;
          }
          _limit = (1 << _numBits) - 1;
          if (_tiffFudge) {
            --_limit;
          }
        }
        _prefix = c & 0xFF;
      }
    }
  }

  /// Flushes any remaining buffered data.
  /// Must be called when compression is complete.
  void flush() {
    if (_prefix != -1) {
      _bf.writeBits(_prefix, _numBits);
    }
    _bf.writeBits(_endOfInfo, _numBits);
    _bf.flush();
  }
}

/// Utility class for LZW compression.
class LZWEncoder {
  LZWEncoder._();

  /// Compresses data using LZW algorithm.
  ///
  /// [data] - Input data to compress
  /// [codeSize] - Initial code size (default: 8 for general data)
  /// [tiff] - Whether to use TIFF LZW variant (default: true)
  ///
  /// Returns compressed data as Uint8List.
  static Uint8List compress(Uint8List data,
      {int codeSize = 8, bool tiff = true}) {
    final output = BytesBuilder();
    final compressor = LZWCompressor(output, codeSize, tiff);
    compressor.compress(data, 0, data.length);
    compressor.flush();
    return output.toBytes();
  }
}
