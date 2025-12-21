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

import 'dart:typed_data';

import 'byte_buffer.dart';

/// Utility class for byte operations, especially for PDF number formatting.
class ByteUtils {
  ByteUtils._();

  /// Whether to use high precision for double formatting.
  static bool highPrecision = false;

  /// Hex digit bytes: 0-9, a-f.
  static final Uint8List _bytes = Uint8List.fromList([
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, // 0-9
    97, 98, 99, 100, 101, 102, // a-f
  ]);

  /// Zero as bytes.
  static final Uint8List _zero = Uint8List.fromList([48]); // '0'

  /// One as bytes.
  static final Uint8List _one = Uint8List.fromList([49]); // '1'

  /// Negative one as bytes.
  static final Uint8List _negOne = Uint8List.fromList([45, 49]); // '-1'

  /// Converts a string to ISO-8859-1 bytes.
  ///
  /// Each character is truncated to 8 bits.
  static Uint8List getIsoBytes(String text) {
    final len = text.length;
    final b = Uint8List(len);
    for (var k = 0; k < len; k++) {
      b[k] = text.codeUnitAt(k) & 0xFF;
    }
    return b;
  }

  /// Converts a string to ISO-8859-1 bytes with prefix.
  static Uint8List getIsoBytesWithPrefix(int pre, String text) {
    return getIsoBytesWithPrefixAndSuffix(pre, text, 0);
  }

  /// Converts a string to ISO-8859-1 bytes with prefix and suffix.
  static Uint8List getIsoBytesWithPrefixAndSuffix(
      int pre, String text, int post) {
    var len = text.length;
    var start = 0;
    if (pre != 0) {
      len++;
      start = 1;
    }
    if (post != 0) {
      len++;
    }
    final b = Uint8List(len);
    if (pre != 0) {
      b[0] = pre & 0xFF;
    }
    if (post != 0) {
      b[len - 1] = post & 0xFF;
    }
    for (var k = 0; k < text.length; k++) {
      b[k + start] = text.codeUnitAt(k) & 0xFF;
    }
    return b;
  }

  /// Converts an integer to ISO bytes.
  static Uint8List getIsoBytesFromInt(int n, [ByteBuffer? buffer]) {
    var negative = false;
    if (n < 0) {
      negative = true;
      n = -n;
    }
    final intLen = _intSize(n);
    final buf = buffer ?? ByteBuffer.withCapacity(intLen + (negative ? 1 : 0));
    for (var i = 0; i < intLen; i++) {
      buf.prepend(_bytes[n % 10]);
      n ~/= 10;
    }
    if (negative) {
      buf.prepend(45); // '-'
    }
    return buffer == null ? buf.getInternalBuffer() : Uint8List(0);
  }

  /// Converts a double to ISO bytes.
  static Uint8List getIsoBytesFromDouble(double d, [ByteBuffer? buffer]) {
    return _getIsoBytesFromDoubleWithPrecision(d, buffer, highPrecision);
  }

  /// Converts a double to ISO bytes with specified precision.
  static Uint8List _getIsoBytesFromDoubleWithPrecision(
    double d,
    ByteBuffer? buffer,
    bool useHighPrecision,
  ) {
    if (useHighPrecision) {
      if (d.abs() < 0.000001) {
        if (buffer != null) {
          buffer.prependBytes(_zero);
          return Uint8List(0);
        } else {
          return _zero;
        }
      }
      if (d.isNaN) {
        // Log warning about NaN
        d = 0;
      }
      final result = getIsoBytes(_formatNumber(d, 6));
      if (buffer != null) {
        buffer.prependBytes(result);
        return Uint8List(0);
      } else {
        return result;
      }
    }

    var negative = false;
    if (d.abs() < 0.000015) {
      if (buffer != null) {
        buffer.prependBytes(_zero);
        return Uint8List(0);
      } else {
        return _zero;
      }
    }

    ByteBuffer buf;
    if (d < 0) {
      negative = true;
      d = -d;
    }

    if (d < 1.0) {
      d += 0.000005;
      if (d >= 1) {
        final result = negative ? _negOne : _one;
        if (buffer != null) {
          buffer.prependBytes(result);
          return Uint8List(0);
        } else {
          return result;
        }
      }
      var v = (d * 100000).toInt();
      var len = 5;
      for (; len > 0; len--) {
        if (v % 10 != 0) {
          break;
        }
        v ~/= 10;
      }
      buf = buffer ?? ByteBuffer.withCapacity(negative ? len + 3 : len + 2);
      for (var i = 0; i < len; i++) {
        buf.prepend(_bytes[v % 10]);
        v ~/= 10;
      }
      buf.prepend(46); // '.'
      buf.prepend(48); // '0'
      if (negative) {
        buf.prepend(45); // '-'
      }
    } else if (d <= 32767) {
      d += 0.005;
      var v = (d * 100).toInt();
      int intLen;
      if (v >= 1000000) {
        intLen = 5;
      } else if (v >= 100000) {
        intLen = 4;
      } else if (v >= 10000) {
        intLen = 3;
      } else if (v >= 1000) {
        intLen = 2;
      } else {
        intLen = 1;
      }

      var fracLen = 0;
      if (v % 100 != 0) {
        // fracLen includes '.'
        fracLen = 2;
        if (v % 10 != 0) {
          fracLen++;
        } else {
          v ~/= 10;
        }
      } else {
        v ~/= 100;
      }

      buf = buffer ??
          ByteBuffer.withCapacity(intLen + fracLen + (negative ? 1 : 0));
      // -1 because fracLen includes '.'
      for (var i = 0; i < fracLen - 1; i++) {
        buf.prepend(_bytes[v % 10]);
        v ~/= 10;
      }
      if (fracLen > 0) {
        buf.prepend(46); // '.'
      }
      for (var i = 0; i < intLen; i++) {
        buf.prepend(_bytes[v % 10]);
        v ~/= 10;
      }
      if (negative) {
        buf.prepend(45); // '-'
      }
    } else {
      d += 0.5;
      int v;
      if (d > 9223372036854775807) {
        v = 9223372036854775807; // max int
      } else {
        if (d.isNaN) {
          // Log warning about NaN
          d = 0;
        }
        v = d.toInt();
      }
      final intLen = _longSize(v);
      buf = buffer ?? ByteBuffer.withCapacity(intLen + (negative ? 1 : 0));
      for (var i = 0; i < intLen; i++) {
        buf.prepend(_bytes[v % 10]);
        v ~/= 10;
      }
      if (negative) {
        buf.prepend(45); // '-'
      }
    }

    return buffer == null ? buf.getInternalBuffer() : Uint8List(0);
  }

  /// Formats a number with specified decimal places.
  static String _formatNumber(double d, int decimals) {
    final str = d.toStringAsFixed(decimals);
    // Remove trailing zeros after decimal point
    if (str.contains('.')) {
      var result = str;
      while (result.endsWith('0')) {
        result = result.substring(0, result.length - 1);
      }
      if (result.endsWith('.')) {
        result = result.substring(0, result.length - 1);
      }
      return result;
    }
    return str;
  }

  /// Returns the number of digits in a long.
  static int _longSize(int l) {
    var m = 10;
    for (var i = 1; i < 19; i++) {
      if (l < m) {
        return i;
      }
      m *= 10;
    }
    return 19;
  }

  /// Returns the number of digits in an int.
  static int _intSize(int l) {
    var m = 10;
    for (var i = 1; i < 10; i++) {
      if (l < m) {
        return i;
      }
      m *= 10;
    }
    return 10;
  }
}
