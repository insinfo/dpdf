/*
 * This file is part of the iText (R) project.
 * Copyright (c) 1998-2025 Apryse Group NV
 * Authors: Apryse Software.
 *
 * This program is offered under a commercial and under the AGPL license.
 * For commercial licensing, contact us at https://itextpdf.com/sales.
 * For AGPL licensing, see below.
 *
 * AGPL licensing:
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:io';
import 'dart:typed_data';

import '../pdf/pdf_array.dart';
import '../pdf/pdf_dictionary.dart';
import '../pdf/pdf_name.dart';

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

  /// Decodes bytes using the filters specified in the stream dictionary.
  ///
  /// [bytes] The raw bytes to decode.
  /// [streamDict] The stream's dictionary containing filter information.
  ///
  /// Returns the decoded bytes.
  static Future<Uint8List> decodeBytes(
      Uint8List bytes, PdfDictionary streamDict) async {
    final filterObj = await streamDict.get(PdfName.filter);
    if (filterObj == null) {
      return bytes;
    }

    final decodeParmsObj = await streamDict.get(PdfName.decodeParms);

    // Single filter
    if (filterObj is PdfName) {
      PdfDictionary? parms;
      if (decodeParmsObj is PdfDictionary) {
        parms = decodeParmsObj;
      } else if (decodeParmsObj is PdfArray) {
        // Some malformed PDFs may provide array even with single filter.
        parms = await decodeParmsObj.getAsDictionary(0);
      }
      return await _applyFilter(bytes, filterObj, parms);
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
        final filter = await filterObj.getAsName(i);
        if (filter == null) continue;

        PdfDictionary? parms;
        if (decodeParmsArray != null && i < decodeParmsArray.size()) {
          parms = await decodeParmsArray.getAsDictionary(i);
        }

        result = await _applyFilter(result, filter, parms);
      }
      return result;
    }

    return bytes;
  }

  /// Applies a single filter to decode bytes.
  static Future<Uint8List> _applyFilter(
      Uint8List bytes, PdfName filter, PdfDictionary? parms) async {
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
        // TODO: Implement CCITTFaxDecode for fax/TIFF images
        return bytes;

      case 'JBIG2Decode':
        // TODO: Implement JBIG2Decode for bi-level images
        return bytes;

      case 'Crypt':
        // Encryption filter - handled by PdfEncryption
        return bytes;

      default:
        // TODO: Log warning for unknown filter
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
        final predictor = await parms.getAsInt(_predictorKey);
        if (predictor != null && predictor > 1) {
          result = await _applyPredictor(result, parms, predictor);
        }
      }

      return result;
    } catch (_) {
      // TODO: Log decompression failure for debugging
      return bytes;
    }
  }

  /// Applies PNG/TIFF predictors for FlateDecode/LZWDecode.
  static Future<Uint8List> _applyPredictor(
      Uint8List bytes, PdfDictionary parms, int predictor) async {
    if (predictor == 1) {
      return bytes;
    }

    final columns = await parms.getAsInt(_columnsKey) ?? 1;
    final colors = await parms.getAsInt(_colorsKey) ?? 1;
    final bitsPerComponent = await parms.getAsInt(_bpcKey) ?? 8;

    final bytesPerPixel = (colors * bitsPerComponent + 7) ~/ 8;
    final bytesPerRow = (columns * colors * bitsPerComponent + 7) ~/ 8;

    // PNG predictors (10-15)
    if (predictor >= 10 && predictor <= 15) {
      return _pngPredictor(bytes, bytesPerRow, bytesPerPixel);
    }

    // TIFF predictor (2)
    if (predictor == 2) {
      return _tiffPredictor(bytes, bytesPerRow, bytesPerPixel);
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

  /// Applies TIFF predictor decoding.
  static Uint8List _tiffPredictor(
      Uint8List bytes, int bytesPerRow, int bytesPerPixel) {
    final numRows = bytesPerRow > 0 ? (bytes.length ~/ bytesPerRow) : 0;
    final output = Uint8List(bytes.length);

    for (var row = 0; row < numRows; row++) {
      final rowStart = row * bytesPerRow;

      for (var i = 0; i < bytesPerRow; i++) {
        if (i < bytesPerPixel) {
          output[rowStart + i] = bytes[rowStart + i];
        } else {
          output[rowStart + i] =
              (bytes[rowStart + i] + output[rowStart + i - bytesPerPixel]) &
                  0xFF;
        }
      }
    }

    return output;
  }

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
    final earlyChange = await parms?.getAsInt(_earlyChangeKey) ?? 1;

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
      final predictor = await parms.getAsInt(_predictorKey);
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
