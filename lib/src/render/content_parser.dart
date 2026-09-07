import 'dart:typed_data';

import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_boolean.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_null.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_string.dart';

/// One operator from a content stream, with the operands that preceded it.
///
/// PDF content is postfix: the operands come first and the operator last, so
/// this is the natural unit to consume a stream in.
class PdfContentOperation {
  /// The operator, e.g. `re`, `Tj`, `cm`. For an inline image this is `BI`.
  final String operator;

  /// Operands in the order they appeared.
  final List<PdfObject> operands;

  /// The dictionary between `BI` and `ID`, for an inline image.
  final PdfDictionary? inlineImage;

  /// The raw sample bytes between `ID` and `EI`, still filtered as stored.
  final Uint8List? inlineImageData;

  const PdfContentOperation(
    this.operator,
    this.operands, {
    this.inlineImage,
    this.inlineImageData,
  });

  /// The operand at [index] as a number, or null when it is not one.
  double? number(int index) {
    if (index < 0 || index >= operands.length) return null;
    final value = operands[index];
    return value is PdfNumber ? value.doubleValue() : null;
  }

  /// The operand at [index] as a name's text, or null when it is not a name.
  String? name(int index) {
    if (index < 0 || index >= operands.length) return null;
    final value = operands[index];
    return value is PdfName ? value.getValue() : null;
  }

  /// Every operand as a number, in order. Null when any of them is not.
  ///
  /// Most geometric operators want exactly this, and want to be skipped
  /// rather than half-applied when the content is malformed.
  List<double>? numbers([int? expected]) {
    if (expected != null && operands.length != expected) return null;
    final result = <double>[];
    for (final operand in operands) {
      if (operand is! PdfNumber) return null;
      result.add(operand.doubleValue());
    }
    return result;
  }

  @override
  String toString() => '${operands.join(' ')} $operator';
}

/// The content stream is not something this parser can read.
class PdfContentException implements Exception {
  final String message;

  /// Byte offset in the content stream where the trouble was found.
  final int offset;

  const PdfContentException(this.message, this.offset);

  @override
  String toString() => 'PdfContentException at $offset: $message';
}

/// Splits a page or form content stream into operators and their operands.
///
/// This is a lexer, not an interpreter: it knows the syntax of PDF content —
/// numbers, names, strings, arrays, inline dictionaries and inline images —
/// and nothing about what the operators mean. That split is what lets the same
/// parser serve a renderer, a text extractor and a content rewriter.
///
/// Inline images are handled here because they cannot be: the bytes between
/// `ID` and `EI` are raw samples that would otherwise be lexed as garbage.
abstract final class PdfContentParser {
  /// Parses [content] lazily.
  ///
  /// Malformed input throws [PdfContentException] at the point of trouble
  /// rather than silently producing nonsense.
  static Iterable<PdfContentOperation> parse(Uint8List content) sync* {
    final reader = _Reader(content);
    var operands = <PdfObject>[];

    while (true) {
      reader.skipWhitespaceAndComments();
      if (reader.atEnd) break;

      final token = reader.readToken();
      if (token == null) break;

      if (token is _Operator) {
        if (token.name == 'BI') {
          yield reader.readInlineImage();
          operands = <PdfObject>[];
          continue;
        }
        yield PdfContentOperation(token.name, operands);
        operands = <PdfObject>[];
        continue;
      }

      if (operands.length >= _maxOperands) {
        throw PdfContentException(
            'More than $_maxOperands operands accumulated with no operator; '
            'the stream is not valid content.',
            reader.offset);
      }
      operands.add(token as PdfObject);
    }
  }

  /// An operator with no operands can legally repeat forever, but operands
  /// cannot pile up without one: that only happens on binary data being lexed
  /// as content.
  static const int _maxOperands = 512;
}

/// Marks an operator token, which is not a PDF object.
class _Operator {
  final String name;
  const _Operator(this.name);
}

class _Reader {
  final Uint8List data;
  int offset = 0;

  _Reader(this.data);

  bool get atEnd => offset >= data.length;

  static const int _maxDepth = 64;

  static bool _isWhitespace(int byte) =>
      byte == 0x00 ||
      byte == 0x09 ||
      byte == 0x0A ||
      byte == 0x0C ||
      byte == 0x0D ||
      byte == 0x20;

  static bool _isDelimiter(int byte) =>
      byte == 0x28 || // (
      byte == 0x29 || // )
      byte == 0x3C || // <
      byte == 0x3E || // >
      byte == 0x5B || // [
      byte == 0x5D || // ]
      byte == 0x7B || // {
      byte == 0x7D || // }
      byte == 0x2F || // /
      byte == 0x25; // %

  void skipWhitespaceAndComments() {
    while (offset < data.length) {
      final byte = data[offset];
      if (_isWhitespace(byte)) {
        offset++;
        continue;
      }
      if (byte == 0x25) {
        // A comment runs to the end of the line.
        while (offset < data.length &&
            data[offset] != 0x0A &&
            data[offset] != 0x0D) {
          offset++;
        }
        continue;
      }
      return;
    }
  }

  /// Reads one token: a PDF object, or an [_Operator]. Null at end of input.
  Object? readToken([int depth = 0]) {
    skipWhitespaceAndComments();
    if (atEnd) return null;
    if (depth > _maxDepth) {
      throw PdfContentException(
          'Content nested deeper than $_maxDepth levels.', offset);
    }

    final byte = data[offset];
    switch (byte) {
      case 0x2F: // /
        return _readName();
      case 0x28: // (
        return _readLiteralString();
      case 0x5B: // [
        return _readArray(depth);
      case 0x5D: // ]
        throw PdfContentException('A ] closes an array never opened.', offset);
      case 0x3C: // <
        if (offset + 1 < data.length && data[offset + 1] == 0x3C) {
          return _readDictionary(depth);
        }
        return _readHexString();
      case 0x3E: // >
        throw PdfContentException(
            'A > closes a dictionary never opened.', offset);
      case 0x7B: // {
      case 0x7D: // }
        // Braces appear only in type 4 function programs, never in content.
        offset++;
        return _Operator(String.fromCharCode(byte));
    }

    if (byte == 0x2B ||
        byte == 0x2D ||
        byte == 0x2E ||
        (byte >= 0x30 && byte <= 0x39)) {
      return _readNumber();
    }
    return _readOperator();
  }

  PdfName _readName() {
    offset++; // the slash
    final buffer = <int>[];
    while (offset < data.length) {
      final byte = data[offset];
      if (_isWhitespace(byte) || _isDelimiter(byte)) break;
      if (byte == 0x23 && offset + 2 < data.length) {
        // #XX is a hex escape for a byte the name syntax cannot hold.
        final hex =
            _hexValue(data[offset + 1]) * 16 + _hexValue(data[offset + 2]);
        if (hex >= 0) {
          buffer.add(hex);
          offset += 3;
          continue;
        }
      }
      buffer.add(byte);
      offset++;
    }
    return PdfName(String.fromCharCodes(buffer));
  }

  static int _hexValue(int byte) {
    if (byte >= 0x30 && byte <= 0x39) return byte - 0x30;
    if (byte >= 0x41 && byte <= 0x46) return byte - 0x41 + 10;
    if (byte >= 0x61 && byte <= 0x66) return byte - 0x61 + 10;
    return -1;
  }

  PdfString _readLiteralString() {
    final start = offset;
    offset++; // the opening parenthesis
    final buffer = <int>[];
    var nesting = 1;

    while (offset < data.length) {
      var byte = data[offset++];
      if (byte == 0x5C) {
        // Backslash escape.
        if (offset >= data.length) break;
        byte = data[offset++];
        switch (byte) {
          case 0x6E: // n
            buffer.add(0x0A);
          case 0x72: // r
            buffer.add(0x0D);
          case 0x74: // t
            buffer.add(0x09);
          case 0x62: // b
            buffer.add(0x08);
          case 0x66: // f
            buffer.add(0x0C);
          case 0x0A: // a backslash at end of line continues the string
            break;
          case 0x0D:
            if (offset < data.length && data[offset] == 0x0A) offset++;
          default:
            if (byte >= 0x30 && byte <= 0x37) {
              // Up to three octal digits.
              var value = byte - 0x30;
              for (var i = 0; i < 2; i++) {
                if (offset >= data.length) break;
                final next = data[offset];
                if (next < 0x30 || next > 0x37) break;
                value = value * 8 + (next - 0x30);
                offset++;
              }
              buffer.add(value & 0xff);
            } else {
              buffer.add(byte);
            }
        }
        continue;
      }
      if (byte == 0x28) {
        nesting++;
        buffer.add(byte);
        continue;
      }
      if (byte == 0x29) {
        nesting--;
        if (nesting == 0) {
          return PdfString.fromBytes(Uint8List.fromList(buffer));
        }
        buffer.add(byte);
        continue;
      }
      buffer.add(byte);
    }
    throw PdfContentException('A ( string is never closed.', start);
  }

  PdfString _readHexString() {
    final start = offset;
    offset++; // the opening angle bracket
    final buffer = <int>[];
    var high = -1;

    while (offset < data.length) {
      final byte = data[offset++];
      if (byte == 0x3E) {
        // An odd trailing digit is padded with a zero.
        if (high >= 0) buffer.add(high * 16);
        return PdfString.fromBytes(Uint8List.fromList(buffer), true);
      }
      if (_isWhitespace(byte)) continue;
      final value = _hexValue(byte);
      if (value < 0) {
        throw PdfContentException(
            'A hex string holds the non-hex byte $byte.', offset - 1);
      }
      if (high < 0) {
        high = value;
      } else {
        buffer.add(high * 16 + value);
        high = -1;
      }
    }
    throw PdfContentException('A < hex string is never closed.', start);
  }

  PdfNumber _readNumber() {
    final start = offset;
    if (offset < data.length &&
        (data[offset] == 0x2B || data[offset] == 0x2D)) {
      offset++;
    }
    while (offset < data.length) {
      final byte = data[offset];
      // A malformed number like `1-2` or `--5` appears in real files; taking
      // the leading run and stopping is what readers do.
      if ((byte >= 0x30 && byte <= 0x39) || byte == 0x2E) {
        offset++;
        continue;
      }
      break;
    }
    final text = String.fromCharCodes(data.sublist(start, offset));
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) {
      // `.` alone, or `-`, or an overflow: treat as zero rather than aborting
      // a page for one bad token.
      return PdfNumber(0);
    }
    return PdfNumber(value);
  }

  Object _readOperator() {
    final start = offset;
    while (offset < data.length) {
      final byte = data[offset];
      if (_isWhitespace(byte) || _isDelimiter(byte)) break;
      offset++;
    }
    if (offset == start) {
      // A delimiter we do not handle; skip it rather than spin forever.
      offset++;
      return _Operator('');
    }
    final text = String.fromCharCodes(data.sublist(start, offset));
    switch (text) {
      case 'true':
        return PdfBoolean(true);
      case 'false':
        return PdfBoolean(false);
      case 'null':
        return PdfNull();
    }
    return _Operator(text);
  }

  PdfArray _readArray(int depth) {
    final start = offset;
    offset++; // [
    final array = PdfArray();
    while (true) {
      skipWhitespaceAndComments();
      if (atEnd) {
        throw PdfContentException('A [ array is never closed.', start);
      }
      if (data[offset] == 0x5D) {
        offset++;
        return array;
      }
      final token = readToken(depth + 1);
      if (token == null) {
        throw PdfContentException('A [ array is never closed.', start);
      }
      if (token is _Operator) {
        // An operator inside an array means the stream is malformed; ignoring
        // it keeps the rest of the array usable.
        continue;
      }
      array.add(token as PdfObject);
    }
  }

  PdfDictionary _readDictionary(int depth) {
    final start = offset;
    offset += 2; // <<
    final dictionary = PdfDictionary();
    while (true) {
      skipWhitespaceAndComments();
      if (atEnd) {
        throw PdfContentException('A << dictionary is never closed.', start);
      }
      if (data[offset] == 0x3E) {
        offset++;
        if (offset < data.length && data[offset] == 0x3E) offset++;
        return dictionary;
      }
      if (data[offset] != 0x2F) {
        throw PdfContentException('A dictionary key is not a name.', offset);
      }
      final key = _readName();
      final value = readToken(depth + 1);
      if (value == null) {
        throw PdfContentException('A << dictionary is never closed.', start);
      }
      if (value is _Operator) continue;
      dictionary.put(key, value as PdfObject);
    }
  }

  /// Reads `BI <dict> ID <bytes> EI`.
  ///
  /// The samples are found by scanning for `EI` at a token boundary, because
  /// an inline image declares no length. That is what the specification leaves
  /// readers to do, and why `EI` can appear inside the data only by accident.
  PdfContentOperation readInlineImage() {
    final dictionary = PdfDictionary();
    while (true) {
      skipWhitespaceAndComments();
      if (atEnd) {
        throw PdfContentException('An inline image has no ID.', offset);
      }
      if (data[offset] == 0x2F) {
        final key = _readName();
        final value = readToken();
        if (value == null || value is _Operator) {
          throw PdfContentException(
              'An inline image key has no value.', offset);
        }
        dictionary.put(key, value as PdfObject);
        continue;
      }
      final token = readToken();
      if (token is _Operator && token.name == 'ID') break;
      if (token == null) {
        throw PdfContentException('An inline image has no ID.', offset);
      }
    }

    // Exactly one whitespace byte separates ID from the samples.
    if (offset < data.length && _isWhitespace(data[offset])) offset++;

    final start = offset;
    var end = -1;
    for (var i = offset; i + 1 < data.length; i++) {
      if (data[i] != 0x45 || data[i + 1] != 0x49) continue; // E I
      final before = i == 0 ? 0x20 : data[i - 1];
      final after = i + 2 < data.length ? data[i + 2] : 0x20;
      if (_isWhitespace(before) &&
          (_isWhitespace(after) ||
              _isDelimiter(after) ||
              i + 2 >= data.length)) {
        end = i;
        break;
      }
    }
    if (end < 0) {
      throw PdfContentException('An inline image has no EI.', start);
    }

    // The whitespace byte before EI belongs to the delimiter, not the data.
    var dataEnd = end;
    if (dataEnd > start && _isWhitespace(data[dataEnd - 1])) dataEnd--;
    final samples = Uint8List.sublistView(data, start, dataEnd);
    offset = end + 2;

    return PdfContentOperation(
      'BI',
      const [],
      inlineImage: dictionary,
      inlineImageData: samples,
    );
  }
}
