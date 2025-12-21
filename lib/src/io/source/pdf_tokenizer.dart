import 'dart:convert';
import 'dart:typed_data';

import '../exceptions/io_exception.dart';
import '../exceptions/io_exception_message_constant.dart';
import 'byte_buffer.dart';
import 'byte_utils.dart';
import 'random_access_file_or_array.dart';

/// Token types recognized by the PDF tokenizer.
enum TokenType {
  number,
  string,
  name,
  comment,
  startArray,
  endArray,
  startDic,
  endDic,
  ref,
  obj,
  endObj,
  other,
  endOfFile,
}

/// PDF tokenizer for parsing PDF files.
///
/// This class is responsible for tokenizing PDF content, recognizing
/// PDF objects like numbers, strings, names, arrays, and dictionaries.
class PdfTokenizer {
  /// "obj" keyword bytes.
  static final Uint8List obj = ByteUtils.getIsoBytes('obj');

  /// "R" keyword bytes.
  static final Uint8List r = ByteUtils.getIsoBytes('R');

  /// "xref" keyword bytes.
  static final Uint8List xref = ByteUtils.getIsoBytes('xref');

  /// "startxref" keyword bytes.
  static final Uint8List startxref = ByteUtils.getIsoBytes('startxref');

  /// "stream" keyword bytes.
  static final Uint8List stream = ByteUtils.getIsoBytes('stream');

  /// "trailer" keyword bytes.
  static final Uint8List trailer = ByteUtils.getIsoBytes('trailer');

  /// "n" keyword bytes.
  static final Uint8List n = ByteUtils.getIsoBytes('n');

  /// "f" keyword bytes.
  static final Uint8List f = ByteUtils.getIsoBytes('f');

  /// "null" keyword bytes.
  static final Uint8List nullBytes = ByteUtils.getIsoBytes('null');

  /// "true" keyword bytes.
  static final Uint8List trueBytes = ByteUtils.getIsoBytes('true');

  /// "false" keyword bytes.
  static final Uint8List falseBytes = ByteUtils.getIsoBytes('false');

  /// Current token type.
  TokenType _type = TokenType.endOfFile;

  /// Object reference number.
  int _reference = 0;

  /// Object generation number.
  int _generation = 0;

  /// Whether current string is hex-encoded.
  bool _hexString = false;

  /// Output buffer for token content.
  final ByteBuffer _outBuf;

  /// The underlying file source.
  final RandomAccessFileOrArray _file;

  /// Whether to close the stream on dispose.
  bool _closeStream = true;

  /// Delimiter table for quick lookup.
  /// Index is character code + 1 to handle -1 (EOF).
  static final List<bool> _delims = _buildDelimsTable();

  /// Builds the delimiter lookup table.
  static List<bool> _buildDelimsTable() {
    final delims = List<bool>.filled(257, false);
    // Mark EOF (-1) as delimiter to prevent infinite loops
    delims[0] = true; // EOF: -1 + 1 = 0
    // Mark delimiters: whitespace and special characters
    // 0 (null), 9 (tab), 10 (LF), 12 (FF), 13 (CR), 32 (space)
    delims[0 + 1] = true; // null (byte 0)
    delims[9 + 1] = true; // tab
    delims[10 + 1] = true; // LF
    delims[12 + 1] = true; // FF
    delims[13 + 1] = true; // CR
    delims[32 + 1] = true; // space
    // Special PDF delimiters
    delims[0x28 + 1] = true; // (
    delims[0x29 + 1] = true; // )
    delims[0x3C + 1] = true; // <
    delims[0x3E + 1] = true; // >
    delims[0x5B + 1] = true; // [
    delims[0x5D + 1] = true; // ]
    delims[0x7B + 1] = true; // {
    delims[0x7D + 1] = true; // }
    delims[0x2F + 1] = true; // /
    delims[0x25 + 1] = true; // %
    return delims;
  }

  /// Creates a PdfTokenizer for the specified RandomAccessFileOrArray.
  ///
  /// The beginning of the file is read to determine the location of the header,
  /// and the data source is adjusted as necessary to account for any junk
  /// that occurs in the byte source before the header.
  PdfTokenizer(this._file) : _outBuf = ByteBuffer();

  /// Seeks to the specified position.
  void seek(int pos) {
    _file.seek(pos);
  }

  /// Reads bytes fully into the provided buffer.
  void readFully(Uint8List bytes) {
    _file.readFully(bytes);
  }

  /// Gets the current position.
  int getPosition() {
    return _file.getPosition();
  }

  /// Closes this tokenizer.
  void close() {
    if (_closeStream) {
      _file.close();
    }
  }

  /// Gets the length of the source.
  int length() {
    return _file.length();
  }

  /// Reads a single byte.
  int read() {
    return _file.read();
  }

  /// Gets the next byte without moving position.
  int peek() {
    return _file.peek();
  }

  /// Gets the next buffer.length bytes without moving position.
  int peekBuffer(Uint8List buffer) {
    return _file.peekBuffer(buffer);
  }

  /// Reads a string of specified size.
  String readString(int size) {
    final buf = StringBuffer();
    int ch;
    while (size-- > 0) {
      ch = read();
      if (ch == -1) {
        break;
      }
      buf.writeCharCode(ch);
    }
    return buf.toString();
  }

  /// Gets the current token type.
  TokenType getTokenType() {
    return _type;
  }

  /// Gets the byte content of the current token.
  Uint8List getByteContent() {
    return _outBuf.toByteArray();
  }

  /// Gets the string value of the current token.
  String getStringValue() {
    return latin1.decode(_outBuf.toByteArray());
  }

  /// Gets the decoded string content (resolves escape sequences).
  Uint8List getDecodedStringContent() {
    return decodeStringContent(
      _outBuf.getInternalBuffer(),
      0,
      _outBuf.size() - 1,
      isHexString(),
    );
  }

  /// Checks if current token value equals the given bytes.
  bool tokenValueEqualsTo(Uint8List cmp) {
    final size = cmp.length;
    if (_outBuf.size() != size) {
      return false;
    }
    final buf = _outBuf.getInternalBuffer();
    for (var i = 0; i < size; i++) {
      if (cmp[i] != buf[i]) {
        return false;
      }
    }
    return true;
  }

  /// Gets the object number of current reference/object token.
  int getObjNr() => _reference;

  /// Gets the generation number of current reference/object token.
  int getGenNr() => _generation;

  /// Pushes back a byte.
  void backOnePosition(int ch) {
    if (ch != -1) {
      _file.pushBack(ch);
    }
  }

  /// Gets the header offset in the file.
  int getHeaderOffset() {
    final str = readString(1024);
    var idx = str.indexOf('%PDF-');
    if (idx < 0) {
      idx = str.indexOf('%FDF-');
      if (idx < 0) {
        throw IoException(IoExceptionMessageConstant.pdfHeaderNotFound);
      }
    }
    return idx;
  }

  /// Checks and returns the PDF header.
  String checkPdfHeader() {
    _file.seek(0);
    final str = readString(1024);
    final idx = str.indexOf('%PDF-');
    if (idx != 0) {
      throw IoException(IoExceptionMessageConstant.pdfHeaderNotFound);
    }
    return str.substring(idx + 1, idx + 8);
  }

  /// Checks the FDF header.
  void checkFdfHeader() {
    _file.seek(0);
    final str = readString(1024);
    final idx = str.indexOf('%FDF-');
    if (idx != 0) {
      throw IoException(IoExceptionMessageConstant.fdfStartxrefNotFound);
    }
  }

  /// Gets the position of startxref.
  int getStartxref() {
    const arrLength = 1024;
    final fileLength = _file.length();
    var pos = fileLength - arrLength;
    if (pos < 1) {
      pos = 1;
    }
    while (pos > 0) {
      _file.seek(pos);
      final str = readString(arrLength);
      final idx = str.lastIndexOf('startxref');
      if (idx >= 0) {
        return pos + idx;
      }
      // 9 = "startxref".length
      pos = pos - arrLength + 9;
    }
    throw IoException(IoExceptionMessageConstant.pdfStartxrefNotFound);
  }

  /// Gets the next %%EOF marker position.
  int getNextEof() {
    const arrLength = 128;
    String str;
    do {
      final currentPosition = _file.getPosition();
      str = readString(arrLength);
      final eofPosition = str.indexOf('%%EOF');
      if (eofPosition >= 0) {
        // Include following EOL bytes
        _file.seek(currentPosition + eofPosition + 5);
        final remainingBytes = readString(4);
        var eolCount = 0;
        for (final b in remainingBytes.codeUnits) {
          if (b == 0x0A || b == 0x0D) {
            // '\n' or '\r'
            eolCount++;
          } else {
            return currentPosition + eofPosition + eolCount + 5;
          }
        }
        return currentPosition + eofPosition + eolCount + 5;
      }
      // Ensure '%%EOF' is not cut in half
      _file.seek(_file.getPosition() - 4);
    } while (str.length > 4);
    throw IoException(IoExceptionMessageConstant.pdfEofNotFound);
  }

  /// Reads the next valid token, resolving references.
  void nextValidToken() {
    var level = 0;
    Uint8List? n1;
    Uint8List? n2;
    var ptr = 0;
    while (nextToken()) {
      if (_type == TokenType.comment) {
        continue;
      }
      switch (level) {
        case 0:
          if (_type != TokenType.number) {
            return;
          }
          ptr = _file.getPosition();
          n1 = getByteContent();
          ++level;
          break;
        case 1:
          if (_type != TokenType.number) {
            _file.seek(ptr);
            _type = TokenType.number;
            _outBuf.reset().appendBytes(n1!);
            return;
          }
          n2 = getByteContent();
          ++level;
          break;
        case 2:
          if (_type == TokenType.other) {
            if (tokenValueEqualsTo(r)) {
              _type = TokenType.ref;
              try {
                _reference = int.parse(latin1.decode(n1!));
                _generation = int.parse(latin1.decode(n2!));
              } catch (e) {
                // Invalid reference
                _reference = -1;
                _generation = 0;
              }
              return;
            } else if (tokenValueEqualsTo(obj)) {
              _type = TokenType.obj;
              _reference = int.parse(latin1.decode(n1!));
              _generation = int.parse(latin1.decode(n2!));
              return;
            }
          }
          _file.seek(ptr);
          _type = TokenType.number;
          _outBuf.reset().appendBytes(n1!);
          return;
      }
    }
    // Handle EOF during level 1
    if (level == 1) {
      _type = TokenType.number;
      _outBuf.reset().appendBytes(n1!);
    }
  }

  /// Reads the next token.
  ///
  /// Returns true if a token was read, false if EOF.
  bool nextToken() {
    int ch;
    _outBuf.reset();
    do {
      ch = _file.read();
    } while (ch != -1 && isWhitespace(ch));

    if (ch == -1) {
      _type = TokenType.endOfFile;
      return false;
    }

    switch (ch) {
      case 0x5B: // '['
        _type = TokenType.startArray;
        break;

      case 0x5D: // ']'
        _type = TokenType.endArray;
        break;

      case 0x2F: // '/'
        _type = TokenType.name;
        while (true) {
          ch = _file.read();
          if (_delims[ch + 1]) {
            break;
          }
          _outBuf.append(ch);
        }
        backOnePosition(ch);
        break;

      case 0x3E: // '>'
        ch = _file.read();
        if (ch != 0x3E) {
          // '>'
          throwError(IoExceptionMessageConstant.gtNotExpected);
        }
        _type = TokenType.endDic;
        break;

      case 0x3C: // '<'
        final v1Initial = _file.read();
        if (v1Initial == 0x3C) {
          // '<'
          _type = TokenType.startDic;
          break;
        }
        _type = TokenType.string;
        _hexString = true;
        var v1 = v1Initial;
        var v2 = 0;
        while (true) {
          while (isWhitespace(v1)) {
            v1 = _file.read();
          }
          if (v1 == 0x3E) {
            // '>'
            break;
          }
          _outBuf.append(v1);
          v1 = ByteBuffer.getHex(v1);
          if (v1 < 0) {
            break;
          }
          v2 = _file.read();
          while (isWhitespace(v2)) {
            v2 = _file.read();
          }
          if (v2 == 0x3E) {
            // '>'
            break;
          }
          _outBuf.append(v2);
          v2 = ByteBuffer.getHex(v2);
          if (v2 < 0) {
            break;
          }
          v1 = _file.read();
        }
        if (v1 < 0 || v2 < 0) {
          throwError(IoExceptionMessageConstant.errorReadingString);
        }
        break;

      case 0x25: // '%'
        _type = TokenType.comment;
        do {
          ch = _file.read();
        } while (ch != -1 && ch != 0x0D && ch != 0x0A); // '\r' '\n'
        break;

      case 0x28: // '('
        _type = TokenType.string;
        _hexString = false;
        var nesting = 0;
        while (true) {
          ch = _file.read();
          if (ch == -1) {
            break;
          }
          if (ch == 0x28) {
            // '('
            ++nesting;
          } else if (ch == 0x29) {
            // ')'
            --nesting;
            if (nesting == -1) {
              break;
            }
          } else if (ch == 0x5C) {
            // '\\'
            _outBuf.append(0x5C);
            ch = _file.read();
            if (ch < 0) {
              break;
            }
          }
          _outBuf.append(ch);
        }
        if (ch == -1) {
          throwError(IoExceptionMessageConstant.errorReadingString);
        }
        break;

      default:
        if (ch == 0x2D ||
            ch == 0x2B ||
            ch == 0x2E ||
            (ch >= 0x30 && ch <= 0x39)) {
          // '-', '+', '.', '0'-'9'
          _type = TokenType.number;
          var isReal = false;
          var numberOfMinuses = 0;
          if (ch == 0x2D) {
            // '-'
            do {
              ++numberOfMinuses;
              ch = _file.read();
            } while (ch == 0x2D);
            _outBuf.append(0x2D);
          } else {
            _outBuf.append(ch);
            ch = _file.read();
          }
          while (ch >= 0x30 && ch <= 0x39) {
            // '0'-'9'
            _outBuf.append(ch);
            ch = _file.read();
          }
          if (ch == 0x2E) {
            // '.'
            isReal = true;
            _outBuf.append(ch);
            ch = _file.read();
            // Check for minus after '.'
            var numberOfMinusesAfterDot = 0;
            if (ch == 0x2D) {
              numberOfMinusesAfterDot++;
              ch = _file.read();
            }
            while (ch >= 0x30 && ch <= 0x39) {
              if (numberOfMinusesAfterDot == 0) {
                _outBuf.append(ch);
              }
              ch = _file.read();
            }
          }
          if (numberOfMinuses > 1 && !isReal) {
            // Multiple minuses for integer = 0
            _outBuf.reset();
            _outBuf.append(0x30); // '0'
          }
        } else {
          _type = TokenType.other;
          do {
            _outBuf.append(ch);
            ch = _file.read();
          } while (!_delims[ch + 1]);
        }
        if (ch != -1) {
          backOnePosition(ch);
        }
        break;
    }
    return true;
  }

  /// Gets the long value of the current token.
  int getLongValue() {
    return int.parse(getStringValue());
  }

  /// Gets the int value of the current token.
  int getIntValue() {
    return int.parse(getStringValue());
  }

  /// Returns true if current string is hex-encoded.
  bool isHexString() => _hexString;

  /// Returns true if stream will be closed on dispose.
  bool isCloseStream() => _closeStream;

  /// Sets whether to close stream on dispose.
  void setCloseStream(bool closeStream) {
    _closeStream = closeStream;
  }

  /// Creates an independent view of the file.
  RandomAccessFileOrArray getSafeFile() {
    return _file.createView();
  }

  /// Decodes string content, resolving escape symbols or hex.
  static Uint8List decodeStringContent(
    Uint8List content,
    int from,
    int to,
    bool hexWriting,
  ) {
    final buffer = ByteBuffer.withCapacity(to - from + 1);

    if (hexWriting) {
      // Hex string: <69546578...>
      var i = from;
      while (i <= to) {
        var v1 = ByteBuffer.getHex(content[i++]);
        if (i > to) {
          buffer.append(v1 << 4);
          break;
        }
        var v2 = content[i++];
        v2 = ByteBuffer.getHex(v2);
        buffer.append((v1 << 4) + v2);
      }
    } else {
      // Literal string: (iText\( some version)...)
      var i = from;
      while (i <= to) {
        var ch = content[i++];
        if (ch == 0x5C) {
          // '\\'
          var lineBreak = false;
          ch = content[i++];
          switch (ch) {
            case 0x6E: // 'n'
              ch = 0x0A; // '\n'
              break;
            case 0x72: // 'r'
              ch = 0x0D; // '\r'
              break;
            case 0x74: // 't'
              ch = 0x09; // '\t'
              break;
            case 0x62: // 'b'
              ch = 0x08; // '\b'
              break;
            case 0x66: // 'f'
              ch = 0x0C; // '\f'
              break;
            case 0x28: // '('
            case 0x29: // ')'
            case 0x5C: // '\\'
              break;
            case 0x0D: // '\r'
              lineBreak = true;
              if (i <= to && content[i++] != 0x0A) {
                i--;
              }
              break;
            case 0x0A: // '\n'
              lineBreak = true;
              break;
            default:
              if (ch < 0x30 || ch > 0x37) {
                // Not octal
                break;
              }
              var octal = ch - 0x30;
              if (i > to) {
                ch = octal;
                break;
              }
              ch = content[i++];
              if (ch < 0x30 || ch > 0x37) {
                i--;
                ch = octal;
                break;
              }
              octal = (octal << 3) + ch - 0x30;
              if (i > to) {
                ch = octal;
                break;
              }
              ch = content[i++];
              if (ch < 0x30 || ch > 0x37) {
                i--;
                ch = octal;
                break;
              }
              octal = (octal << 3) + ch - 0x30;
              ch = octal & 0xFF;
              break;
          }
          if (lineBreak) {
            continue;
          }
        } else if (ch == 0x0D) {
          // '\r'
          ch = 0x0A; // '\n'
          if (i <= to && content[i++] != 0x0A) {
            i--;
          }
        }
        buffer.append(ch);
      }
    }
    return buffer.toByteArray();
  }

  /// Decodes string content from full array.
  static Uint8List decodeStringContentFull(Uint8List content, bool hexWriting) {
    return decodeStringContent(content, 0, content.length - 1, hexWriting);
  }

  /// Checks if a character is whitespace.
  ///
  /// Whitespace: 0 (null), 9 (tab), 10 (LF), 12 (FF), 13 (CR), 32 (space)
  static bool isWhitespace(int ch, [bool isNullWhitespace = true]) {
    return ((isNullWhitespace && ch == 0) ||
        ch == 9 ||
        ch == 10 ||
        ch == 12 ||
        ch == 13 ||
        ch == 32);
  }

  /// Checks if a character is a delimiter.
  static bool isDelimiter(int ch) {
    return (ch == 0x28 ||
        ch == 0x29 ||
        ch == 0x3C ||
        ch == 0x3E ||
        ch == 0x5B ||
        ch == 0x5D ||
        ch == 0x2F ||
        ch == 0x25);
  }

  /// Checks if a character is a delimiter or whitespace.
  static bool isDelimiterWhitespace(int ch) {
    return _delims[ch + 1];
  }

  /// Throws an error with file position information.
  void throwError(String error, [List<Object>? messageParams]) {
    final innerException = IoException(error);
    if (messageParams != null) {
      innerException.setMessageParams(messageParams);
    }
    throw IoException.full(
      IoExceptionMessageConstant.errorAtFilePointer,
      innerException,
      null,
    ).setMessageParams([_file.getPosition()]);
  }

  /// Checks whether line equals to 'trailer'.
  static bool checkTrailer(ByteBuffer line) {
    if (trailer.length > line.size()) {
      return false;
    }
    for (var i = 0; i < trailer.length; i++) {
      if (trailer[i] != line.get(i)) {
        return false;
      }
    }
    return true;
  }

  /// Reads data into the provided ByteBuffer.
  ///
  /// Skips initial whitespace.
  bool readLineSegment(ByteBuffer buffer, [bool isNullWhitespace = true]) {
    int c;
    var eol = false;

    // Skip initial whitespace
    while (isWhitespace((c = read()), isNullWhitespace)) {}

    var prevWasWhitespace = false;
    while (!eol) {
      switch (c) {
        case -1:
        case 0x0A: // '\n'
          eol = true;
          break;

        case 0x0D: // '\r'
          eol = true;
          final cur = getPosition();
          if (read() != 0x0A) {
            seek(cur);
          }
          break;

        case 9: // tab
        case 12: // formfeed
        case 32: // space
          if (prevWasWhitespace) {
            break;
          }
          prevWasWhitespace = true;
          buffer.append(c);
          break;

        default:
          prevWasWhitespace = false;
          buffer.append(c);
          break;
      }

      if (eol || buffer.size() == buffer.capacity()) {
        eol = true;
      } else {
        c = read();
      }
    }

    // Skip rest of line if buffer full
    if (buffer.size() == buffer.capacity()) {
      eol = false;
      while (!eol) {
        switch (c = read()) {
          case -1:
          case 0x0A:
            eol = true;
            break;
          case 0x0D:
            eol = true;
            final cur = getPosition();
            if (read() != 0x0A) {
              seek(cur);
            }
            break;
        }
      }
    }

    return !(c == -1 && buffer.isEmpty());
  }

  /// Check whether line starts with object declaration.
  ///
  /// Returns [objectNumber, generation] if check is successful, otherwise null.
  static List<int>? checkObjectStart(PdfTokenizer lineTokenizer) {
    try {
      lineTokenizer.seek(0);
      if (!lineTokenizer.nextToken() ||
          lineTokenizer.getTokenType() != TokenType.number) {
        return null;
      }
      final num = lineTokenizer.getIntValue();
      if (!lineTokenizer.nextToken() ||
          lineTokenizer.getTokenType() != TokenType.number) {
        return null;
      }
      final gen = lineTokenizer.getIntValue();
      if (!lineTokenizer.nextToken()) {
        return null;
      }
      if (!_arraysEquals(obj, lineTokenizer.getByteContent())) {
        return null;
      }
      return [num, gen];
    } catch (e) {
      // Empty on purpose
    }
    return null;
  }

  /// Helper to compare byte arrays.
  static bool _arraysEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
