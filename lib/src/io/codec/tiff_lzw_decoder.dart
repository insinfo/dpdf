import 'dart:typed_data';
import '../exceptions/io_exception.dart';

/// Decodes TIFF 6.0 LZW strips using prefix links and one-byte suffixes.
/// All strip state belongs to the call, so a decoder can be reused.
class TIFFLZWDecoder {
  final int _width;
  final int _predictor;
  final int _samples;

  TIFFLZWDecoder(this._width, this._predictor, this._samples);

  Uint8List decode(Uint8List data, Uint8List uncompData, int h) {
    if (_predictor != 1 && _predictor != 2) {
      throw ArgumentError.value(_predictor, 'predictor', 'Expected 1 or 2.');
    }
    if (_predictor == 2 &&
        (_width <= 0 ||
            _samples <= 0 ||
            h < 0 ||
            _width * _samples * h > uncompData.length)) {
      throw ArgumentError(
          'The output buffer must contain the requested pixel rows.');
    }
    if (data.length > 1 && data[0] == 0 && data[1] == 1) {
      throw IoException('This strip uses the obsolete TIFF LZW bit order.');
    }

    final prefixes = Uint16List(4096);
    final suffixes = Uint8List(4096);
    final stack = Uint8List(4096);
    var available = 258;
    var codeWidth = 9;
    var previous = -1;
    var bitOffset = 0;
    var written = 0;

    while (written < uncompData.length &&
        bitOffset + codeWidth <= data.length * 8) {
      var symbol = 0;
      for (var bit = 0; bit < codeWidth; bit++) {
        final position = bitOffset++;
        symbol =
            (symbol << 1) | ((data[position ~/ 8] >> (7 - position % 8)) & 1);
      }
      if (symbol == 257) break;
      if (symbol == 256) {
        available = 258;
        codeWidth = 9;
        previous = -1;
        continue;
      }
      final special = symbol == available && previous >= 0;
      if (symbol > available ||
          (symbol == available && !special) ||
          (previous < 0 && symbol >= 256)) {
        throw IoException('LZW strip refers to an undefined dictionary entry.');
      }

      var cursor = special ? previous : symbol;
      var depth = 0;
      while (cursor >= 258) {
        stack[depth++] = suffixes[cursor];
        cursor = prefixes[cursor];
      }
      final firstByte = cursor;
      stack[depth++] = firstByte;
      while (depth > 0 && written < uncompData.length) {
        uncompData[written++] = stack[--depth];
      }
      if (special && written < uncompData.length) {
        uncompData[written++] = firstByte;
      }

      if (previous >= 0 && available < 4096) {
        prefixes[available] = previous;
        suffixes[available] = firstByte;
        available++;
        // TIFF changes code width one dictionary entry before a full power of 2.
        if (codeWidth < 12 && available == (1 << codeWidth) - 1) codeWidth++;
      }
      previous = symbol;
    }

    if (_predictor == 2) {
      final rowBytes = _width * _samples;
      for (var row = 0; row < h; row++) {
        final end = (row + 1) * rowBytes;
        for (var position = row * rowBytes + _samples;
            position < end;
            position++) {
          uncompData[position] =
              (uncompData[position] + uncompData[position - _samples]) & 255;
        }
      }
    }
    // Retain the previous API's tolerance of strips without a final EOI code.
    return uncompData;
  }
}

class LZWDecoder {
  LZWDecoder._();

  static Uint8List decode(
    Uint8List data, {
    required int expectedSize,
    int width = 0,
    int predictor = 1,
    int samplesPerPixel = 1,
    int height = 1,
  }) {
    RangeError.checkNotNegative(expectedSize, 'expectedSize');
    return TIFFLZWDecoder(width, predictor, samplesPerPixel)
        .decode(data, Uint8List(expectedSize), height);
  }
}
