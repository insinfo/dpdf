import 'dart:typed_data';

import 'byte_buffer.dart';

/// Utility class for byte operations, especially for PDF number formatting.
class ByteUtils {
  ByteUtils._();

  /// Whether to use high precision for double formatting.
  static bool highPrecision = false;

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
    return _deliver(n.toString(), buffer);
  }

  /// Writes a decimal PDF token without exponent notation.
  /// Normal precision retains five fractional digits below one and two up to
  /// 32767. Larger magnitudes round to integers, capped at signed 64-bit max.
  static Uint8List getIsoBytesFromDouble(double value, [ByteBuffer? buffer]) {
    if (value.isNaN) return _deliver('0', buffer);
    final magnitude = value.abs();
    final cutoff = highPrecision ? 0.000001 : 0.000015;
    if (magnitude < cutoff) return _deliver('0', buffer);
    String text;
    if (magnitude.isInfinite || (!highPrecision && magnitude > 32767)) {
      final ceiling = (BigInt.one << 63) - BigInt.one;
      final rounded =
          magnitude.isInfinite ? ceiling : BigInt.from(magnitude + 0.5);
      text = (rounded > ceiling ? ceiling : rounded).toString();
    } else {
      final places = highPrecision ? 6 : (magnitude < 1 ? 5 : 2);
      text = magnitude.toStringAsFixed(places);
      if (text.contains('e') || text.contains('E')) {
        text = BigInt.from(magnitude).toString();
      } else {
        text = text
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
      }
    }
    return _deliver(value.isNegative && text != '0' ? '-$text' : text, buffer);
  }

  static Uint8List _deliver(String text, ByteBuffer? destination) {
    final bytes = Uint8List.fromList(text.codeUnits);
    if (destination == null) return bytes;
    destination.prependBytes(bytes);
    return Uint8List(0);
  }

  /// Checks if two strings are equal, ignoring case.
  static bool equalsIgnoreCase(String? s1, String? s2) {
    if (s1 == s2) return true;
    if (s1 == null || s2 == null) return false;
    return s1.toLowerCase() == s2.toLowerCase();
  }
}
