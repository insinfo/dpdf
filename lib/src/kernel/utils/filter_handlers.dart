import 'dart:typed_data';

import 'package:jbig2/jbig2.dart';

import '../../platform/compression.dart';

import '../../io/exceptions/io_exception.dart';
import '../../io/codec/ccitt_g4_encoder.dart';
import '../../io/codec/lzw_compressor.dart';
import '../../io/codec/tiff_fax_decoder.dart';
import '../../io/codec/tiff_constants.dart';
import '../pdf/pdf_array.dart';
import '../pdf/pdf_dictionary.dart';
import '../pdf/pdf_name.dart';
import '../pdf/pdf_stream.dart';

/// Handles decoding of PDF stream filters.
///
/// This class provides methods to decode data compressed or encoded
/// using various PDF filter algorithms.
class FilterHandlers {
  FilterHandlers._();

  // Cached PdfName instances to avoid recreation in hot paths.
  static final PdfName _predictorKey = PdfName('Predictor');
  static final PdfName _columnsKey = PdfName('Columns');
  static final PdfName _colorsKey = PdfName('Colors');
  static final PdfName _bpcKey = PdfName('BitsPerComponent');
  static final PdfName _earlyChangeKey = PdfName('EarlyChange');
  static final PdfName _kKey = PdfName('K');
  static final PdfName _rowsKey = PdfName('Rows');
  static final PdfName _blackIs1Key = PdfName('BlackIs1');
  static final PdfName _encodedByteAlignKey = PdfName('EncodedByteAlign');
  static final PdfName _endOfLineKey = PdfName('EndOfLine');
  static final PdfName _damagedRowsKey = PdfName('DamagedRowsBeforeError');
  static final PdfName _heightKey = PdfName('Height');

  /// Decodes bytes using the filters specified in the stream dictionary.
  ///
  /// [bytes] The raw bytes to decode.
  /// [streamDict] The stream's dictionary containing filter information.
  ///
  /// Returns the decoded bytes.
  static Future<Uint8List> decodeBytes(
      Uint8List bytes, PdfDictionary streamDict) async {
    final filterObj = await streamDict.get(PdfName.filter, true);
    if (filterObj == null) {
      return bytes;
    }

    final decodeParmsObj = await streamDict.get(PdfName.decodeParms, true);

    // Single filter
    if (filterObj is PdfName) {
      PdfDictionary? parms;
      if (decodeParmsObj is PdfDictionary) {
        parms = decodeParmsObj;
      } else if (decodeParmsObj is PdfArray) {
        // Some malformed PDFs may provide array even with single filter.
        parms = await decodeParmsObj.dictionaryEntry(0);
      }
      return await _applyFilter(bytes, filterObj, parms, streamDict);
    }

    // Array of filters
    if (filterObj is PdfArray) {
      var result = bytes;

      final int n = filterObj.size();
      PdfArray? decodeParmsArray;
      if (decodeParmsObj is PdfArray) {
        decodeParmsArray = decodeParmsObj;
      }

      for (var i = 0; i < n; i++) {
        final filter = await filterObj.nameEntry(i);
        if (filter == null) continue;

        PdfDictionary? parms;
        if (decodeParmsArray != null && i < decodeParmsArray.size()) {
          parms = await decodeParmsArray.dictionaryEntry(i);
        }

        result = await _applyFilter(result, filter, parms, streamDict);
      }
      return result;
    }

    return bytes;
  }

  /// Applies a single filter to decode bytes.
  static Future<Uint8List> _applyFilter(
      Uint8List bytes, PdfName filter, PdfDictionary? parms,
      [PdfDictionary? streamDict]) async {
    final filterName = filter.getValue();

    switch (filterName) {
      case 'FlateDecode':
      case 'Fl':
        return await _flateDecode(bytes, parms);

      case 'ASCIIHexDecode':
      case 'AHx':
        return _asciiHexDecode(bytes);

      case 'ASCII85Decode':
      case 'A85':
        return _ascii85Decode(bytes);

      case 'LZWDecode':
      case 'LZW':
        return await _lzwDecode(bytes, parms);

      case 'RunLengthDecode':
      case 'RL':
        return _runLengthDecode(bytes);

      case 'DCTDecode':
      case 'DCT':
        // JPEG images - pass through (decoded by image library)
        return bytes;

      case 'JPXDecode':
        // JPEG2000 images - pass through (decoded by image library)
        return bytes;

      case 'CCITTFaxDecode':
      case 'CCF':
        return await _ccittFaxDecode(bytes, parms, streamDict);

      case 'JBIG2Decode':
        return await _jbig2Decode(bytes, parms);

      case 'Crypt':
        // 7.4.10: the filter only names the crypt filter that the security
        // handler shall use, and /Identity (the default) means the data is
        // untouched. The handler decrypts a stream before its filter chain is
        // applied, so the bytes arriving here are plaintext in both cases.
        return bytes;

      default:
        print('Warning: unknown filter: $filterName');
        return bytes;
    }
  }

  /// Decodes FlateDecode (zlib) compressed data.
  static Future<Uint8List> _flateDecode(
      Uint8List bytes, PdfDictionary? parms) async {
    try {
      final decompressed = zlib.decode(bytes);
      var result = _toUint8List(decompressed);

      // Apply predictor if specified
      if (parms != null) {
        final predictor = await parms.integerEntry(_predictorKey);
        if (predictor != null && predictor > 1) {
          result = await _applyPredictor(result, parms, predictor);
        }
      }

      return result;
    } catch (e) {
      print('Error: decompression failure: $e');
      return bytes;
    }
  }

  /// Applies PNG/TIFF predictors for FlateDecode/LZWDecode.
  static Future<Uint8List> _applyPredictor(
      Uint8List bytes, PdfDictionary parms, int predictor) async {
    if (predictor == 1) {
      return bytes;
    }

    final columns = await parms.integerEntry(_columnsKey) ?? 1;
    final colors = await parms.integerEntry(_colorsKey) ?? 1;
    final bitsPerComponent = await parms.integerEntry(_bpcKey) ?? 8;

    return undoPredictor(bytes,
        predictor: predictor,
        colors: colors,
        bitsPerComponent: bitsPerComponent,
        columns: columns);
  }

  /// Reverses the predictor stage of `LZWDecode`/`FlateDecode` (ISO 32000-1,
  /// 7.4.4.4).
  ///
  /// [predictor] 1 (none), 2 (TIFF Predictor 2) or 10..15 (PNG group; the row
  /// tag in the data selects the algorithm, so every PNG value behaves alike).
  static Uint8List undoPredictor(Uint8List bytes,
      {required int predictor,
      int colors = 1,
      int bitsPerComponent = 8,
      int columns = 1}) {
    if (predictor <= 1) return bytes;
    if (colors < 1 || columns < 1 || bitsPerComponent < 1) return bytes;

    final bytesPerPixel = (colors * bitsPerComponent + 7) ~/ 8;
    final bytesPerRow = (columns * colors * bitsPerComponent + 7) ~/ 8;

    // PNG predictors (10-15)
    if (predictor >= 10 && predictor <= 15) {
      return _pngPredictor(bytes, bytesPerRow, bytesPerPixel);
    }

    // TIFF predictor (2)
    if (predictor == 2) {
      return _tiffPredictor(bytes, columns, colors, bitsPerComponent);
    }

    return bytes;
  }

  /// Applies the predictor stage that `undoPredictor` reverses.
  ///
  /// PNG values pick one algorithm for every row: 10 None, 11 Sub, 12 Up,
  /// 13 Average, 14 Paeth and 15 the per-row optimum (ISO 32000-1, Table 10).
  static Uint8List applyPredictor(Uint8List bytes,
      {required int predictor,
      int colors = 1,
      int bitsPerComponent = 8,
      int columns = 1}) {
    if (predictor <= 1) return bytes;
    if (colors < 1 || columns < 1 || bitsPerComponent < 1) return bytes;

    final bytesPerPixel = (colors * bitsPerComponent + 7) ~/ 8;
    final bytesPerRow = (columns * colors * bitsPerComponent + 7) ~/ 8;

    if (predictor >= 10 && predictor <= 15) {
      return _pngPredictorEncode(
          bytes, bytesPerRow, bytesPerPixel, predictor - 10);
    }
    if (predictor == 2) {
      return _tiffPredictorEncode(bytes, columns, colors, bitsPerComponent);
    }
    return bytes;
  }

  /// Applies PNG predictor decoding.
  static Uint8List _pngPredictor(
      Uint8List bytes, int bytesPerRow, int bytesPerPixel) {
    final rowSize = bytesPerRow + 1; // +1 for filter byte
    if (rowSize <= 1 || bytes.isEmpty) return Uint8List(0);

    final numRows = bytes.length ~/ rowSize;
    final output = Uint8List(numRows * bytesPerRow);

    for (var row = 0; row < numRows; row++) {
      final rowStart = row * rowSize;
      final outStart = row * bytesPerRow;
      final filterType = bytes[rowStart];

      final prevOutStart = (row - 1) * bytesPerRow;
      final bool hasPrev = row > 0;

      for (var i = 0; i < bytesPerRow; i++) {
        final rawByte = bytes[rowStart + 1 + i];

        final left =
            i >= bytesPerPixel ? output[outStart + i - bytesPerPixel] : 0;
        final up = hasPrev ? output[prevOutStart + i] : 0;
        final upLeft = (hasPrev && i >= bytesPerPixel)
            ? output[prevOutStart + i - bytesPerPixel]
            : 0;

        int value;
        switch (filterType) {
          case 0: // None
            value = rawByte;
            break;
          case 1: // Sub
            value = (rawByte + left) & 0xFF;
            break;
          case 2: // Up
            value = (rawByte + up) & 0xFF;
            break;
          case 3: // Average
            value = (rawByte + ((left + up) >> 1)) & 0xFF;
            break;
          case 4: // Paeth
            value = (rawByte + _paethPredictor(left, up, upLeft)) & 0xFF;
            break;
          default:
            value = rawByte;
        }

        output[outStart + i] = value;
      }
    }

    return output;
  }

  /// Paeth predictor function.
  static int _paethPredictor(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs();
    final pb = (p - b).abs();
    final pc = (p - c).abs();

    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
  }

  /// Encodes with a single PNG predictor algorithm, or the per-row optimum.
  static Uint8List _pngPredictorEncode(
      Uint8List bytes, int bytesPerRow, int bytesPerPixel, int algorithm) {
    if (bytesPerRow <= 0) return Uint8List(0);
    final numRows = (bytes.length + bytesPerRow - 1) ~/ bytesPerRow;
    final output = Uint8List(numRows * (bytesPerRow + 1));
    final row = Uint8List(bytesPerRow);
    final prev = Uint8List(bytesPerRow);
    final candidate = Uint8List(bytesPerRow);

    for (var r = 0; r < numRows; r++) {
      final start = r * bytesPerRow;
      final available = bytes.length - start;
      final count = available < bytesPerRow ? available : bytesPerRow;
      row.fillRange(0, bytesPerRow, 0);
      row.setRange(0, count, bytes, start);

      var chosen = algorithm;
      if (algorithm == 5) {
        var bestScore = -1;
        for (var type = 0; type <= 4; type++) {
          _pngFilterRow(row, prev, bytesPerPixel, type, candidate);
          var score = 0;
          for (var i = 0; i < bytesPerRow; i++) {
            final v = candidate[i];
            score += v < 128 ? v : 256 - v;
          }
          if (bestScore < 0 || score < bestScore) {
            bestScore = score;
            chosen = type;
          }
        }
      }

      _pngFilterRow(row, prev, bytesPerPixel, chosen, candidate);
      final outStart = r * (bytesPerRow + 1);
      output[outStart] = chosen;
      output.setRange(outStart + 1, outStart + 1 + bytesPerRow, candidate);
      prev.setRange(0, bytesPerRow, row);
    }
    return output;
  }

  static void _pngFilterRow(Uint8List row, Uint8List prev, int bytesPerPixel,
      int type, Uint8List out) {
    for (var i = 0; i < row.length; i++) {
      final left = i >= bytesPerPixel ? row[i - bytesPerPixel] : 0;
      final up = prev[i];
      final upLeft = i >= bytesPerPixel ? prev[i - bytesPerPixel] : 0;
      switch (type) {
        case 1:
          out[i] = (row[i] - left) & 0xFF;
          break;
        case 2:
          out[i] = (row[i] - up) & 0xFF;
          break;
        case 3:
          out[i] = (row[i] - ((left + up) >> 1)) & 0xFF;
          break;
        case 4:
          out[i] = (row[i] - _paethPredictor(left, up, upLeft)) & 0xFF;
          break;
        default:
          out[i] = row[i];
      }
    }
  }

  /// Applies TIFF Predictor 2 decoding.
  ///
  /// The prediction is per colour component of a sample, so the bit depth and
  /// the component count both matter: a 16-bit component wraps at 65536 and
  /// sub-byte components are unpacked from the row's bit stream. Treating the
  /// row as a flat byte array is only correct when `BitsPerComponent` is 8.
  static Uint8List _tiffPredictor(
      Uint8List bytes, int columns, int colors, int bitsPerComponent) {
    final bytesPerRow = (columns * colors * bitsPerComponent + 7) ~/ 8;
    if (bytesPerRow <= 0) return bytes;
    final numRows = bytes.length ~/ bytesPerRow;
    final output = Uint8List.fromList(bytes);
    final samplesPerRow = columns * colors;

    for (var row = 0; row < numRows; row++) {
      final base = row * bytesPerRow;
      if (bitsPerComponent == 8) {
        for (var i = colors; i < bytesPerRow; i++) {
          output[base + i] = (output[base + i] + output[base + i - colors]) &
              0xFF;
        }
      } else if (bitsPerComponent == 16) {
        final step = colors * 2;
        for (var i = step; i + 1 < bytesPerRow; i += 2) {
          final previous =
              (output[base + i - step] << 8) | output[base + i - step + 1];
          final current = (output[base + i] << 8) | output[base + i + 1];
          final value = (current + previous) & 0xFFFF;
          output[base + i] = (value >> 8) & 0xFF;
          output[base + i + 1] = value & 0xFF;
        }
      } else {
        final mask = (1 << bitsPerComponent) - 1;
        for (var s = colors; s < samplesPerRow; s++) {
          final previous =
              _getSample(output, base, s - colors, bitsPerComponent);
          final current = _getSample(output, base, s, bitsPerComponent);
          _setSample(
              output, base, s, bitsPerComponent, (current + previous) & mask);
        }
      }
    }

    return output;
  }

  /// Applies TIFF Predictor 2 encoding, the exact inverse of [_tiffPredictor].
  static Uint8List _tiffPredictorEncode(
      Uint8List bytes, int columns, int colors, int bitsPerComponent) {
    final bytesPerRow = (columns * colors * bitsPerComponent + 7) ~/ 8;
    if (bytesPerRow <= 0) return bytes;
    final numRows = bytes.length ~/ bytesPerRow;
    final output = Uint8List.fromList(bytes);
    final samplesPerRow = columns * colors;

    for (var row = 0; row < numRows; row++) {
      final base = row * bytesPerRow;
      if (bitsPerComponent == 8) {
        for (var i = bytesPerRow - 1; i >= colors; i--) {
          output[base + i] =
              (bytes[base + i] - bytes[base + i - colors]) & 0xFF;
        }
      } else if (bitsPerComponent == 16) {
        final step = colors * 2;
        // A 16 bit sample starts on an even byte offset, and the last one of
        // the row starts at bytesPerRow - 2. Starting anywhere odd would walk
        // a grid the decoder never visits and the two would never agree.
        for (var i = bytesPerRow - 2; i >= step; i -= 2) {
          final previous =
              (bytes[base + i - step] << 8) | bytes[base + i - step + 1];
          final current = (bytes[base + i] << 8) | bytes[base + i + 1];
          final value = (current - previous) & 0xFFFF;
          output[base + i] = (value >> 8) & 0xFF;
          output[base + i + 1] = value & 0xFF;
        }
      } else {
        final mask = (1 << bitsPerComponent) - 1;
        for (var s = samplesPerRow - 1; s >= colors; s--) {
          final previous =
              _getSample(bytes, base, s - colors, bitsPerComponent);
          final current = _getSample(bytes, base, s, bitsPerComponent);
          _setSample(
              output, base, s, bitsPerComponent, (current - previous) & mask);
        }
      }
    }

    return output;
  }

  static int _getSample(Uint8List data, int rowBase, int index, int bits) {
    final bitPosition = index * bits;
    final byteIndex = rowBase + (bitPosition >> 3);
    if (byteIndex >= data.length) return 0;
    final shift = 8 - bits - (bitPosition & 7);
    return (data[byteIndex] >> shift) & ((1 << bits) - 1);
  }

  static void _setSample(
      Uint8List data, int rowBase, int index, int bits, int value) {
    final bitPosition = index * bits;
    final byteIndex = rowBase + (bitPosition >> 3);
    if (byteIndex >= data.length) return;
    final shift = 8 - bits - (bitPosition & 7);
    final mask = ((1 << bits) - 1) << shift;
    data[byteIndex] = (data[byteIndex] & ~mask & 0xFF) | ((value << shift) & mask);
  }

  /// Decodes `/ASCIIHexDecode` data (ISO 32000-1, 7.4.2).
  static Uint8List asciiHexDecode(Uint8List bytes) => _asciiHexDecode(bytes);

  /// Decodes `/ASCII85Decode` data (ISO 32000-1, 7.4.3).
  static Uint8List ascii85Decode(Uint8List bytes) => _ascii85Decode(bytes);

  /// Decodes `/RunLengthDecode` data (ISO 32000-1, 7.4.5).
  static Uint8List runLengthDecode(Uint8List bytes) => _runLengthDecode(bytes);

  /// Decodes ASCIIHexDecode data.
  static Uint8List _asciiHexDecode(Uint8List bytes) {
    final out = Uint8List((bytes.length >> 1) + 2);
    var outLen = 0;
    var firstNibble = -1;

    for (var i = 0; i < bytes.length; i++) {
      final ch = bytes[i];
      if (ch == 0x3E) break;
      if (ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D || ch == 0x0C) {
        continue;
      }

      int nibble;
      if (ch >= 0x30 && ch <= 0x39) {
        nibble = ch - 0x30;
      } else if (ch >= 0x41 && ch <= 0x46) {
        nibble = ch - 0x41 + 10;
      } else if (ch >= 0x61 && ch <= 0x66) {
        nibble = ch - 0x61 + 10;
      } else {
        continue;
      }

      if (firstNibble < 0) {
        firstNibble = nibble;
      } else {
        out[outLen++] = (firstNibble << 4) | nibble;
        firstNibble = -1;
      }
    }

    if (firstNibble >= 0) {
      out[outLen++] = (firstNibble << 4);
    }

    return Uint8List.view(out.buffer, out.offsetInBytes, outLen);
  }

  /// Decodes ASCII85Decode data.
  static Uint8List _ascii85Decode(Uint8List bytes) {
    final out = _GrowableBytes(((bytes.length * 4) ~/ 5) + 16);
    var tuple = 0;
    var count = 0;

    for (var i = 0; i < bytes.length; i++) {
      final ch = bytes[i];
      if (ch == 0x7E && i + 1 < bytes.length && bytes[i + 1] == 0x3E) {
        break;
      }
      if (ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D || ch == 0x0C) {
        continue;
      }
      if (ch == 0x7A && count == 0) {
        out.addRepeat(0, 4);
        continue;
      }
      if (ch < 0x21 || ch > 0x75) continue;

      tuple = tuple * 85 + (ch - 0x21);
      count++;

      if (count == 5) {
        out.addByte((tuple >> 24) & 0xFF);
        out.addByte((tuple >> 16) & 0xFF);
        out.addByte((tuple >> 8) & 0xFF);
        out.addByte(tuple & 0xFF);
        tuple = 0;
        count = 0;
      }
    }

    if (count > 1) {
      for (var n = count; n < 5; n++) {
        tuple = tuple * 85 + 84;
      }
      for (var n = 0; n < count - 1; n++) {
        out.addByte((tuple >> (24 - n * 8)) & 0xFF);
      }
    }

    return out.takeBytes();
  }

  /// Decodes LZWDecode data.
  static Future<Uint8List> _lzwDecode(
      Uint8List bytes, PdfDictionary? parms) async {
    final earlyChange = await parms?.integerEntry(_earlyChangeKey) ?? 1;

    const clearCode = 256;
    const eodCode = 257;
    const maxCode = 4096;

    final prefix = Int32List(maxCode);
    prefix.fillRange(0, maxCode, -1);

    final suffix = Uint8List(maxCode);
    for (var i = 0; i < 256; i++) {
      suffix[i] = i;
    }

    final stack = Uint8List(maxCode);
    final out = _GrowableBytes(bytes.length * 2);

    var nextCode = 258;
    var codeSize = 9;

    var bytePos = 0;
    var bitBuffer = 0;
    var bitsInBuffer = 0;

    int readCode() {
      while (bitsInBuffer < codeSize) {
        if (bytePos >= bytes.length) return -1;
        bitBuffer = (bitBuffer << 8) | (bytes[bytePos++] & 0xFF);
        bitsInBuffer += 8;
      }
      bitsInBuffer -= codeSize;
      final code = (bitBuffer >> bitsInBuffer) & ((1 << codeSize) - 1);
      bitBuffer &= (bitsInBuffer == 0) ? 0 : ((1 << bitsInBuffer) - 1);
      return code;
    }

    void resetTable() {
      nextCode = 258;
      codeSize = 9;
    }

    var oldCode = -1;
    var oldFirstChar = 0;

    while (true) {
      final code = readCode();
      if (code < 0) break;
      if (code == eodCode) break;
      if (code == clearCode) {
        resetTable();
        oldCode = -1;
        continue;
      }

      int curCode = code;
      bool special = false;

      if (curCode == nextCode && oldCode >= 0) {
        curCode = oldCode;
        special = true;
      } else if (curCode > nextCode) {
        break;
      }

      var top = 0;
      var t = curCode;
      while (t >= 256) {
        stack[top++] = suffix[t];
        t = prefix[t];
        if (t < 0) break;
      }
      if (t < 0) break;

      stack[top++] = t;
      var firstChar = stack[top - 1];

      for (var i = top - 1; i >= 0; i--) {
        out.addByte(stack[i]);
      }

      if (special) {
        out.addByte(oldFirstChar);
        firstChar = oldFirstChar;
      }

      if (oldCode >= 0 && nextCode < maxCode) {
        prefix[nextCode] = oldCode;
        suffix[nextCode] = firstChar;
        nextCode++;
        if (codeSize < 12 && (nextCode + earlyChange) == (1 << codeSize)) {
          codeSize++;
        }
      }
      oldCode = code;
      oldFirstChar = firstChar;
    }

    var result = out.takeBytes();

    if (parms != null) {
      final predictor = await parms.integerEntry(_predictorKey);
      if (predictor != null && predictor > 1) {
        result = await _applyPredictor(result, parms, predictor);
      }
    }

    return result;
  }

  /// Decodes RunLengthDecode data.
  static Uint8List _runLengthDecode(Uint8List bytes) {
    final out = _GrowableBytes(bytes.length);
    var i = 0;
    while (i < bytes.length) {
      final len = bytes[i++];
      if (len == 128) break;
      if (len < 128) {
        final count = len + 1;
        final end = (i + count <= bytes.length) ? (i + count) : bytes.length;
        out.addBytes(bytes, i, end);
        i = end;
      } else {
        if (i >= bytes.length) break;
        final repeatByte = bytes[i++];
        final count = 257 - len;
        out.addRepeat(repeatByte, count);
      }
    }
    return out.takeBytes();
  }

  /// Decodes CCITTFaxDecode data.
  static Future<Uint8List> _ccittFaxDecode(
      Uint8List bytes, PdfDictionary? parms,
      [PdfDictionary? streamDict]) async {
    final k = (await parms?.integerEntry(_kKey)) ?? 0;
    var columns = (await parms?.integerEntry(_columnsKey)) ?? 1728;
    if (columns <= 0) columns = 1728;
    int rows = (await parms?.integerEntry(_rowsKey)) ?? 0;
    if (rows <= 0 && streamDict != null) {
      rows = (await streamDict.integerEntry(_heightKey)) ?? 0;
    }
    final blackIs1 = (await parms?.flagEntry(_blackIs1Key)) ?? false;
    final encodedByteAlign =
        (await parms?.flagEntry(_encodedByteAlignKey)) ?? false;
    final endOfLine = (await parms?.flagEntry(_endOfLineKey)) ?? false;
    final damagedRowsBeforeError =
        (await parms?.integerEntry(_damagedRowsKey)) ?? 0;

    return ccittFaxDecode(bytes,
        k: k,
        columns: columns,
        rows: rows,
        blackIs1: blackIs1,
        encodedByteAlign: encodedByteAlign,
        endOfLine: endOfLine,
        damagedRowsBeforeError: damagedRowsBeforeError);
  }

  /// Decodes `/CCITTFaxDecode` data (ISO 32000-1, 7.4.6).
  ///
  /// [k] selects the coding scheme: negative is pure two-dimensional (Group 4,
  /// ITU-T T.6), zero is pure one-dimensional (Group 3 1-D) and positive is the
  /// mixed Group 3 2-D scheme. Only the sign is significant, as Table 11
  /// requires.
  ///
  /// [encodedByteAlign] makes every encoded scan line start on a byte
  /// boundary. [rows] of 0 leaves the height undetermined, in which case the
  /// data is decoded until it runs out and the result is trimmed to the rows
  /// that were actually produced.
  ///
  /// The result follows the PDF convention for 1-bit image samples, so a 0 bit
  /// is black unless [blackIs1] is set; the fax decoders themselves always
  /// produce a 1 bit for black.
  ///
  /// [damagedRowsBeforeError] applies only when [endOfLine] is set and [k] is
  /// non-negative: up to that many damaged rows are replaced by the previous
  /// row (or by a white line when the previous row was damaged too) and a
  /// larger number of damaged rows is an error.
  static Uint8List ccittFaxDecode(Uint8List bytes,
      {int k = 0,
      int columns = 1728,
      int rows = 0,
      bool blackIs1 = false,
      bool encodedByteAlign = false,
      bool endOfLine = false,
      int damagedRowsBeforeError = 0}) {
    if (columns <= 0) columns = 1728;
    final rowBytes = (columns + 7) ~/ 8;

    var height = rows;
    final heightWasGiven = height > 0;
    if (!heightWasGiven) {
      if (bytes.isEmpty) return Uint8List(0);
      // Table 11: an absent or zero /Rows leaves the height undetermined. One
      // encoded bit is the shortest a scan line can be, which bounds the row
      // count; the buffer is trimmed afterwards to the rows really decoded.
      height = bytes.length * 8;
      const maxOutputBytes = 8 * 1024 * 1024;
      final cap = maxOutputBytes ~/ rowBytes;
      if (height > cap) height = cap;
      if (height < 1) height = 1;
    }

    var buffer = Uint8List(rowBytes * height);
    var decoder = TIFFFaxDecoder(1, columns, height);

    try {
      if (k < 0) {
        // Group 4. The decoder reads EncodedByteAlign through the fill-bits
        // option, which makes it skip to the next byte boundary per line.
        final options = encodedByteAlign ? TiffConstants.group3optFillbits : 0;
        decoder.decodeT6(buffer, bytes, 0, height, options);
      } else if (k > 0) {
        // Mixed one- and two-dimensional Group 3. Every line is introduced by
        // an EOL code followed by a tag bit, so the EOL-driven decoder is
        // required here.
        var options = TiffConstants.group3opt2dencoding;
        if (encodedByteAlign) options |= TiffConstants.group3optFillbits;
        decoder.setOptions(TiffConstants.compressionCcittfax3, options, 0);
        decoder.decodeT4(buffer, bytes);
      } else {
        // Group 3 one-dimensional. EOL codes are optional in PDF, so pick the
        // decoder that matches the data instead of always assuming they exist.
        final options = encodedByteAlign ? TiffConstants.group3optFillbits : 0;
        decoder.setOptions(TiffConstants.compressionCcittfax3, options, 0);
        if (endOfLine || _startsWithEol(bytes)) {
          decoder.decodeT4(buffer, bytes);
          if (decoder.fails > 0) {
            final fallback = Uint8List(buffer.length);
            final failsWithEol = decoder.fails;
            final retry = TIFFFaxDecoder(1, columns, height);
            retry.setOptions(TiffConstants.compressionCcittrle, options, 0);
            retry.decodeRLE(fallback, bytes);
            if (retry.fails < failsWithEol) {
              buffer = fallback;
              decoder = retry;
            }
          }
        } else if (encodedByteAlign) {
          // Byte-aligned lines are exactly what the RLE path assumes.
          decoder.setOptions(TiffConstants.compressionCcittrle, options, 0);
          decoder.decodeRLE(buffer, bytes);
        } else {
          decoder.decode1D(buffer, bytes, 0, height);
        }
      }
    } on IoException {
      // Truncated or malformed encoded data. Whatever was decoded up to that
      // point is still usable image data, so keep it rather than losing the
      // whole image; a fully undecodable stream still raises.
      if (decoder.rowsDecoded <= 0) rethrow;
    } on RangeError {
      if (decoder.rowsDecoded <= 0) rethrow;
    }

    _substituteDamagedRows(buffer, rowBytes, decoder.damagedRows,
        decoder.rowsDecoded, endOfLine, k, damagedRowsBeforeError);
    return _finishCcitt(buffer, rowBytes, decoder.rowsDecoded, heightWasGiven,
        blackIs1, columns);
  }

  /// True when the data opens with the 12-bit EOL pattern 000000000001.
  static bool _startsWithEol(Uint8List bytes) {
    if (bytes.length < 2) return false;
    return bytes[0] == 0 && (bytes[1] & 0xF0) == 0x10;
  }

  static void _substituteDamagedRows(
      Uint8List buffer,
      int rowBytes,
      List<int> damagedRows,
      int rowsDecoded,
      bool endOfLine,
      int k,
      int tolerance) {
    if (damagedRows.isEmpty) return;
    if (!endOfLine || k < 0) return;
    if (damagedRows.length > tolerance) {
      throw FormatException('CCITTFaxDecode found ${damagedRows.length} '
          'damaged rows, more than the $tolerance tolerated by '
          'DamagedRowsBeforeError.');
    }
    final damaged = damagedRows.toSet();
    for (final row in damagedRows) {
      if (row < 0 || (row + 1) * rowBytes > buffer.length) continue;
      final start = row * rowBytes;
      if (row > 0 && !damaged.contains(row - 1)) {
        buffer.setRange(start, start + rowBytes, buffer, start - rowBytes);
      } else {
        buffer.fillRange(start, start + rowBytes, 0);
      }
    }
  }

  static Uint8List _finishCcitt(Uint8List buffer, int rowBytes, int rowsDecoded,
      bool heightWasGiven, bool blackIs1, int columns) {
    var result = buffer;
    if (!heightWasGiven) {
      final produced = rowsDecoded * rowBytes;
      if (produced <= 0) return Uint8List(0);
      if (produced < buffer.length) {
        result = Uint8List.sublistView(buffer, 0, produced);
      }
    }
    // The decoders emit 1 for black; PDF wants 0 for black unless BlackIs1.
    if (!blackIs1) {
      for (var i = 0; i < result.length; i++) {
        result[i] = ~result[i] & 0xFF;
      }
    }
    // A row occupies whole bytes, so any Columns that is not a multiple of
    // eight leaves spare bits at the end of the row. The standard says nothing
    // about them and a consumer ignores them, but the inversion above just
    // turned the decoder's zeroes into ones. Normalising them to zero is what
    // makes the output of a decode deterministic, and what lets an encode
    // followed by a decode return the bytes it started from.
    final spare = rowBytes * 8 - columns;
    if (spare > 0) {
      final mask = (0xFF << spare) & 0xFF;
      for (var row = 0; (row + 1) * rowBytes <= result.length; row++) {
        result[row * rowBytes + rowBytes - 1] &= mask;
      }
    }
    return result;
  }

  /// Decodes JBIG2 compressed data.
  /// Decodes a `/JBIG2Decode` stream to packed 1-bit rows.
  ///
  /// The filter's output follows the PDF convention, where a 0 bit is black,
  /// which is the opposite of JBIG2's own; `toPdfImageData` performs that
  /// inversion and whitens the padding bits at the end of each row.
  ///
  /// A stream that will not decode is returned untouched rather than throwing,
  /// so one damaged image does not stop a whole page from loading.
  static Future<Uint8List> _jbig2Decode(
      Uint8List bytes, PdfDictionary? parms) async {
    Uint8List? globals;
    if (parms != null) {
      final globalsObject = await parms.get(PdfName('JBIG2Globals'), true);
      if (globalsObject is PdfStream) {
        globals = await globalsObject.getBytes(true);
      }
    }
    try {
      return decodeJbig2Embedded(bytes, globals: globals).toPdfImageData();
    } on Jbig2Exception {
      return bytes;
    }
  }

  // ===========================================================================
  // Encoding (ISO 32000-1, 7.4). Every encoder below is the exact inverse of
  // the decoder with the same name, so `decode(encode(x)) == x`.
  // ===========================================================================

  /// Encodes [bytes] with the single filter named by [filter].
  ///
  /// [parms] carries the same decode parameters that the resulting stream
  /// shall declare in `/DecodeParms`, so that decoding with that dictionary
  /// reproduces [bytes] exactly. Filters whose data is an opaque image
  /// bitstream - `/DCTDecode`, `/JPXDecode`, `/JBIG2Decode` - and `/Crypt` are
  /// not produced here and throw [UnsupportedError].
  static Future<Uint8List> encodeBytes(Uint8List bytes, PdfName filter,
      [PdfDictionary? parms]) async {
    switch (filter.getValue()) {
      case 'FlateDecode':
      case 'Fl':
        return flateEncode(await _encodePredictor(bytes, parms));
      case 'LZWDecode':
      case 'LZW':
        final earlyChange = await parms?.integerEntry(_earlyChangeKey) ?? 1;
        return lzwEncode(await _encodePredictor(bytes, parms),
            earlyChange: earlyChange);
      case 'ASCIIHexDecode':
      case 'AHx':
        return asciiHexEncode(bytes);
      case 'ASCII85Decode':
      case 'A85':
        return ascii85Encode(bytes);
      case 'RunLengthDecode':
      case 'RL':
        return runLengthEncode(bytes);
      case 'CCITTFaxDecode':
      case 'CCF':
        final k = await parms?.integerEntry(_kKey) ?? 0;
        if (k >= 0) {
          throw UnsupportedError(
              'CCITTFaxDecode encoding supports Group 4 only (K < 0).');
        }
        var columns = await parms?.integerEntry(_columnsKey) ?? 1728;
        if (columns <= 0) columns = 1728;
        final rows = await parms?.integerEntry(_rowsKey) ?? 0;
        final blackIs1 = await parms?.flagEntry(_blackIs1Key) ?? false;
        return ccittFaxEncode(bytes,
            columns: columns, rows: rows, blackIs1: blackIs1);
      default:
        throw UnsupportedError(
            'Encoding the ${filter.getValue()} filter is not supported.');
    }
  }

  static Future<Uint8List> _encodePredictor(
      Uint8List bytes, PdfDictionary? parms) async {
    if (parms == null) return bytes;
    final predictor = await parms.integerEntry(_predictorKey);
    if (predictor == null || predictor <= 1) return bytes;
    return applyPredictor(bytes,
        predictor: predictor,
        colors: await parms.integerEntry(_colorsKey) ?? 1,
        bitsPerComponent: await parms.integerEntry(_bpcKey) ?? 8,
        columns: await parms.integerEntry(_columnsKey) ?? 1);
  }

  /// Encodes [bytes] as `/FlateDecode` data.
  static Uint8List flateEncode(Uint8List bytes, {int level = -1}) {
    return _toUint8List(level < 0
        ? zlib.encode(bytes)
        : ZLibEncoder(level: level).convert(bytes));
  }

  /// Encodes [bytes] as `/ASCIIHexDecode` data, terminated by the EOD marker.
  static Uint8List asciiHexEncode(Uint8List bytes) {
    const digits = '0123456789ABCDEF';
    final out = Uint8List(bytes.length * 2 + 1);
    var position = 0;
    for (final b in bytes) {
      out[position++] = digits.codeUnitAt((b >> 4) & 0x0F);
      out[position++] = digits.codeUnitAt(b & 0x0F);
    }
    out[position] = 0x3E; // '>'
    return out;
  }

  /// Encodes [bytes] as `/ASCII85Decode` data, terminated by `~>`.
  ///
  /// A four-byte group of zeros is written as the single character `z`, as
  /// 7.4.3 allows, and a final partial group is truncated to its significant
  /// characters.
  static Uint8List ascii85Encode(Uint8List bytes) {
    final out = _GrowableBytes(bytes.length + bytes.length ~/ 4 + 8);
    var index = 0;
    while (index + 4 <= bytes.length) {
      final tuple = (bytes[index] << 24) |
          (bytes[index + 1] << 16) |
          (bytes[index + 2] << 8) |
          bytes[index + 3];
      index += 4;
      if (tuple == 0) {
        out.addByte(0x7A); // 'z'
        continue;
      }
      _writeBase85(out, tuple, 5);
    }
    final remaining = bytes.length - index;
    if (remaining > 0) {
      var tuple = 0;
      for (var i = 0; i < 4; i++) {
        tuple = (tuple << 8) | (i < remaining ? bytes[index + i] : 0);
      }
      _writeBase85(out, tuple, remaining + 1);
    }
    out.addByte(0x7E); // '~'
    out.addByte(0x3E); // '>'
    return out.takeBytes();
  }

  static void _writeBase85(_GrowableBytes out, int tuple, int count) {
    final digits = List<int>.filled(5, 0);
    var value = tuple;
    for (var i = 4; i >= 0; i--) {
      digits[i] = value % 85;
      value = value ~/ 85;
    }
    for (var i = 0; i < count; i++) {
      out.addByte(0x21 + digits[i]);
    }
  }

  /// Encodes [bytes] as `/RunLengthDecode` data, terminated by the EOD byte.
  ///
  /// Runs of two or more equal bytes become a repeat run; everything else is
  /// gathered into literal runs of at most 128 bytes (7.4.5).
  static Uint8List runLengthEncode(Uint8List bytes) {
    final out = _GrowableBytes(bytes.length + bytes.length ~/ 128 + 2);
    var index = 0;
    while (index < bytes.length) {
      var runLength = 1;
      while (index + runLength < bytes.length &&
          runLength < 128 &&
          bytes[index + runLength] == bytes[index]) {
        runLength++;
      }
      if (runLength > 1) {
        out.addByte(257 - runLength);
        out.addByte(bytes[index]);
        index += runLength;
        continue;
      }
      // Gather literals until a run of three or more starts, which is the
      // shortest run where coding it separately is a win.
      var literal = 1;
      while (index + literal < bytes.length && literal < 128) {
        final b = bytes[index + literal];
        if (index + literal + 2 < bytes.length &&
            bytes[index + literal + 1] == b &&
            bytes[index + literal + 2] == b) {
          break;
        }
        literal++;
      }
      out.addByte(literal - 1);
      out.addBytes(bytes, index, index + literal);
      index += literal;
    }
    out.addByte(128); // EOD
    return out.takeBytes();
  }

  /// Encodes [bytes] as `/LZWDecode` data.
  ///
  /// [earlyChange] matches the filter parameter of the same name: 1, the
  /// default, increases the code length one code early (7.4.4.2).
  static Uint8List lzwEncode(Uint8List bytes, {int earlyChange = 1}) {
    return LZWEncoder.compress(bytes,
        codeSize: 8, tiff: true, earlyChange: earlyChange != 0);
  }

  /// Encodes 1-bit image samples as `/CCITTFaxDecode` Group 4 data (K < 0).
  ///
  /// [bytes] holds packed rows of [columns] pixels using the PDF convention,
  /// so a 0 bit is black unless [blackIs1] is set. [rows] may be 0, in which
  /// case it is derived from the length of [bytes].
  static Uint8List ccittFaxEncode(Uint8List bytes,
      {required int columns, int rows = 0, bool blackIs1 = false}) {
    if (columns <= 0) {
      throw ArgumentError.value(columns, 'columns', 'must be positive');
    }
    final rowBytes = (columns + 7) ~/ 8;
    var height = rows;
    if (height <= 0) height = bytes.length ~/ rowBytes;
    if (height <= 0) return Uint8List(0);
    if (bytes.length < rowBytes * height) {
      throw ArgumentError('CCITTFaxDecode encoding needs $rowBytes bytes per '
          'row for $height rows, but got ${bytes.length}.');
    }

    // The encoder works on 1 = black, which is the BlackIs1 convention.
    var source = Uint8List.sublistView(bytes, 0, rowBytes * height);
    if (!blackIs1) {
      final inverted = Uint8List(source.length);
      for (var i = 0; i < source.length; i++) {
        inverted[i] = ~source[i] & 0xFF;
      }
      source = inverted;
    }
    return CCITTG4Encoder.compress(source, columns, height);
  }

  static Uint8List _toUint8List(List<int> bytes) {
    if (bytes is Uint8List) return bytes;
    return Uint8List.fromList(bytes);
  }
}

final class _GrowableBytes {
  Uint8List _buf;
  int _len = 0;

  _GrowableBytes([int initialCapacity = 256])
      : _buf = Uint8List(initialCapacity < 0 ? 0 : initialCapacity);

  void _ensureCapacity(int additional) {
    final needed = _len + additional;
    if (needed <= _buf.length) return;
    var newCap = _buf.isEmpty ? 256 : _buf.length;
    while (newCap < needed) {
      newCap = newCap < 1024 * 1024 ? (newCap << 1) : (newCap + (newCap >> 1));
    }
    final nb = Uint8List(newCap);
    if (_len > 0) nb.setRange(0, _len, _buf);
    _buf = nb;
  }

  void addByte(int b) {
    _ensureCapacity(1);
    _buf[_len++] = b & 0xFF;
  }

  void addRepeat(int b, int count) {
    if (count <= 0) return;
    _ensureCapacity(count);
    final v = b & 0xFF;
    for (var i = 0; i < count; i++) {
      _buf[_len++] = v;
    }
  }

  void addBytes(Uint8List src, int start, int end) {
    final count = end - start;
    if (count <= 0) return;
    _ensureCapacity(count);
    _buf.setRange(_len, _len + count, src, start);
    _len += count;
  }

  Uint8List takeBytes() {
    return Uint8List.view(_buf.buffer, _buf.offsetInBytes, _len);
  }
}
