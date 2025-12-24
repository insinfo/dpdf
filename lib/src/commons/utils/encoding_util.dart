import 'dart:convert';
import 'dart:typed_data';

/// Helper class for internal usage only.
/// TODO ? Be aware that its API and functionality may be changed in future.
class EncodingUtil {
  EncodingUtil._();

  /// Latin-1 (ISO-8859-1) encoding.
  static const Encoding iso_8859_1 = latin1;

  /// UTF-8 encoding.
  static const Encoding utf8Encoding = utf8;

  /// Converts to byte array from a String, taking the provided encoding into account.
  ///
  /// For PDF purposes, common encodings are:
  /// - 'UTF-8'
  /// - 'ISO-8859-1' (Latin-1)
  /// - 'UTF-16BE' (for Unicode)
  static Uint8List convertToBytes(String text, String encoding) {
    final enc = getEncoding(encoding);
    return Uint8List.fromList(enc.encode(text));
  }

  /// Converts to byte array from a list of char codes.
  static Uint8List convertCharCodesToBytes(List<int> chars, String encoding) {
    final text = String.fromCharCodes(chars);
    return convertToBytes(text, encoding);
  }

  /// Converts to String an array of bytes, taking the provided encoding into account.
  static String convertToString(Uint8List bytes, String encoding) {
    final upperName = encoding.toUpperCase();

    // Handle UTF-8 BOM
    if (upperName == 'UTF-8' &&
        bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }

    // Handle unmarked Unicode variants
    if (upperName == 'UNICODEBIGUNMARKED') {
      return _decodeUtf16(bytes, bigEndian: true);
    } else if (upperName == 'UNICODELITTLEUNMARKED') {
      return _decodeUtf16(bytes, bigEndian: false);
    }

    // Handle BOM markers for Unicode
    bool hasBom = false;
    bool isBigEndian = false;
    int offset = 0;

    if (bytes.length >= 2) {
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        hasBom = true;
        isBigEndian = true;
        offset = 2;
      } else if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        hasBom = true;
        isBigEndian = false;
        offset = 2;
      }
    }

    if (upperName == 'UNICODEBIG') {
      return _decodeUtf16(bytes.sublist(offset),
          bigEndian: !hasBom || isBigEndian);
    } else if (upperName == 'UNICODELITTLE') {
      return _decodeUtf16(bytes.sublist(offset),
          bigEndian: hasBom && isBigEndian);
    }

    final enc = getEncoding(encoding);
    return enc.decode(bytes);
  }

  /// Gets the Encoding for the given encoding name.
  static Encoding getEncoding(String encodingName) {
    final upperName = encodingName.toUpperCase();
    switch (upperName) {
      case 'UTF-8':
      case 'UTF8':
        return utf8;
      case 'ISO-8859-1':
      case 'ISO_8859_1':
      case 'LATIN1':
      case 'LATIN-1':
        return latin1;
      case 'ASCII':
      case 'US-ASCII':
        return ascii;
      case 'UTF-16':
      case 'UTF16':
      case 'UTF-16BE':
      case 'UTF16BE':
      case 'UNICODEBIG':
      case 'UNICODEBIGUNMARKED':
        return _Utf16BeCodec();
      case 'UTF-16LE':
      case 'UTF16LE':
      case 'UNICODELITTLE':
      case 'UNICODELITTLEUNMARKED':
        return _Utf16LeCodec();
      default:
        // Default to Latin-1 for unknown encodings (common in PDF)
        return latin1;
    }
  }

  /// Decodes UTF-16 bytes to a String.
  static String _decodeUtf16(List<int> bytes, {required bool bigEndian}) {
    if (bytes.length % 2 != 0) {
      throw ArgumentError('UTF-16 bytes must be even length');
    }

    final codeUnits = <int>[];
    for (int i = 0; i < bytes.length; i += 2) {
      int codeUnit;
      if (bigEndian) {
        codeUnit = (bytes[i] << 8) | bytes[i + 1];
      } else {
        codeUnit = bytes[i] | (bytes[i + 1] << 8);
      }
      codeUnits.add(codeUnit);
    }
    return String.fromCharCodes(codeUnits);
  }
}

/// UTF-16 Big Endian codec for PDF.
class _Utf16BeCodec extends Encoding {
  @override
  Converter<List<int>, String> get decoder => _Utf16BeDecoder();

  @override
  Converter<String, List<int>> get encoder => _Utf16BeEncoder();

  @override
  String get name => 'UTF-16BE';
}

class _Utf16BeDecoder extends Converter<List<int>, String> {
  @override
  String convert(List<int> input) {
    if (input.length % 2 != 0) {
      throw FormatException('UTF-16BE bytes must be even length');
    }
    final codeUnits = <int>[];
    for (int i = 0; i < input.length; i += 2) {
      codeUnits.add((input[i] << 8) | input[i + 1]);
    }
    return String.fromCharCodes(codeUnits);
  }
}

class _Utf16BeEncoder extends Converter<String, List<int>> {
  @override
  List<int> convert(String input) {
    final bytes = <int>[];
    for (int i = 0; i < input.length; i++) {
      final codeUnit = input.codeUnitAt(i);
      bytes.add((codeUnit >> 8) & 0xFF);
      bytes.add(codeUnit & 0xFF);
    }
    return bytes;
  }
}

/// UTF-16 Little Endian codec for PDF.
class _Utf16LeCodec extends Encoding {
  @override
  Converter<List<int>, String> get decoder => _Utf16LeDecoder();

  @override
  Converter<String, List<int>> get encoder => _Utf16LeEncoder();

  @override
  String get name => 'UTF-16LE';
}

class _Utf16LeDecoder extends Converter<List<int>, String> {
  @override
  String convert(List<int> input) {
    if (input.length % 2 != 0) {
      throw FormatException('UTF-16LE bytes must be even length');
    }
    final codeUnits = <int>[];
    for (int i = 0; i < input.length; i += 2) {
      codeUnits.add(input[i] | (input[i + 1] << 8));
    }
    return String.fromCharCodes(codeUnits);
  }
}

class _Utf16LeEncoder extends Converter<String, List<int>> {
  @override
  List<int> convert(String input) {
    final bytes = <int>[];
    for (int i = 0; i < input.length; i++) {
      final codeUnit = input.codeUnitAt(i);
      bytes.add(codeUnit & 0xFF);
      bytes.add((codeUnit >> 8) & 0xFF);
    }
    return bytes;
  }
}
