import 'dart:typed_data';

/// Bit writer for LZW compression.
/// Handles bit-level output with optional GIF block counting.
class BitFile {
  final BytesBuilder _output;
  final bool _blocks;
  final Uint8List _buffer;
  int _index;
  int _bitsLeft;

  /// Creates a BitFile for bit-level output.
  ///
  /// [blocks] - If true, includes GIF-style block counts in output.
  BitFile(this._output, this._blocks)
      : _buffer = Uint8List(256),
        _index = 0,
        _bitsLeft = 8;

  /// Flushes any remaining buffered data to the output.
  void flush() {
    int numBytes = _index + (_bitsLeft == 8 ? 0 : 1);
    if (numBytes > 0) {
      if (_blocks) {
        _output.addByte(numBytes);
      }
      _output.add(_buffer.sublist(0, numBytes));
      _buffer[0] = 0;
      _index = 0;
      _bitsLeft = 8;
    }
  }

  /// Writes the specified number of bits to the output.
  void writeBits(int bits, int numbits) {
    const int numBytes = 255;

    do {
      // Handle GIF block count when buffer is full
      if ((_index == 254 && _bitsLeft == 0) || _index > 254) {
        if (_blocks) {
          _output.addByte(numBytes);
        }
        _output.add(_buffer.sublist(0, numBytes));
        _buffer[0] = 0;
        _index = 0;
        _bitsLeft = 8;
      }

      // Bits content fits in current index byte
      if (numbits <= _bitsLeft) {
        if (_blocks) {
          // GIF format
          _buffer[_index] |= ((bits & ((1 << numbits) - 1)) << (8 - _bitsLeft));
        } else {
          // TIFF format
          _buffer[_index] |=
              ((bits & ((1 << numbits) - 1)) << (_bitsLeft - numbits));
        }
        _bitsLeft -= numbits;
        numbits = 0;
      } else {
        // Bits overflow from current byte to next
        if (_blocks) {
          // GIF: lowest order bits go to current byte
          _buffer[_index] |=
              ((bits & ((1 << _bitsLeft) - 1)) << (8 - _bitsLeft));
          bits >>= _bitsLeft;
          numbits -= _bitsLeft;
          _buffer[++_index] = 0;
          _bitsLeft = 8;
        } else {
          // TIFF: highest order bits go to current byte
          int topbits =
              (bits >> (numbits - _bitsLeft)) & ((1 << _bitsLeft) - 1);
          _buffer[_index] |= topbits;
          numbits -= _bitsLeft;
          _buffer[++_index] = 0;
          _bitsLeft = 8;
        }
      }
    } while (numbits != 0);
  }
}
