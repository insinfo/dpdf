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

import 'dart:convert';
import 'dart:typed_data';

import 'i_random_access_source.dart';
import 'independent_random_access_source.dart';
import 'thread_safe_random_access_source.dart';

/// Exception thrown when unexpected end of stream is reached.
class EndOfStreamException implements Exception {
  final String message;
  EndOfStreamException([this.message = 'Unexpected end of stream']);

  @override
  String toString() => 'EndOfStreamException: $message';
}

/// Class that is used to unify reading from random access files and arrays.
class RandomAccessFileOrArray {
  /// The source that backs this object.
  IRandomAccessSource _byteSource;

  /// The physical location in the underlying byte source.
  int _byteSourcePosition = 0;

  /// The pushed back byte, if any.
  int _back = 0;

  /// Whether there is a pushed back byte.
  bool _isBack = false;

  /// Creates a RandomAccessFileOrArray that wraps the specified byte source.
  ///
  /// The byte source will be closed when this RandomAccessFileOrArray is closed.
  RandomAccessFileOrArray(this._byteSource);

  /// Creates an independent view of this object (with its own file pointer and push back queue).
  ///
  /// Closing the new object will not close this object.
  /// Closing this object will have adverse effect on the view.
  RandomAccessFileOrArray createView() {
    _ensureByteSourceIsThreadSafe();
    return RandomAccessFileOrArray(IndependentRandomAccessSource(_byteSource));
  }

  /// Creates the view of the byte source of this object.
  ///
  /// Closing the view won't affect this object.
  /// Closing source will have adverse effect on the view.
  IRandomAccessSource createSourceView() {
    _ensureByteSourceIsThreadSafe();
    return IndependentRandomAccessSource(_byteSource);
  }

  /// Pushes a byte back.
  ///
  /// The next get() will return this byte instead of the value from the underlying data source.
  void pushBack(int b) {
    _back = b & 0xFF;
    _isBack = true;
  }

  /// Reads a single byte.
  ///
  /// Returns the byte, or -1 if EOF is reached.
  int read() {
    if (_isBack) {
      _isBack = false;
      return _back & 0xFF;
    }
    return _byteSource.get(_byteSourcePosition++);
  }

  /// Gets the next byte without moving current position.
  ///
  /// Returns the next byte, or -1 if EOF is reached.
  int peek() {
    if (_isBack) {
      return _back & 0xFF;
    }
    return _byteSource.get(_byteSourcePosition);
  }

  /// Gets the next `buffer.length` bytes without moving current position.
  ///
  /// Returns the number of read bytes. If it is less than buffer.length
  /// it means EOF has been reached.
  int peekBuffer(Uint8List buffer) {
    var offset = 0;
    var length = buffer.length;
    var count = 0;
    if (_isBack && length > 0) {
      buffer[offset++] = _back;
      --length;
      ++count;
    }
    if (length > 0) {
      final byteSourceCount =
          _byteSource.getRange(_byteSourcePosition, buffer, offset, length);
      if (byteSourceCount > 0) {
        count += byteSourceCount;
      }
    }
    return count;
  }

  /// Reads the specified amount of bytes to the buffer applying the offset.
  ///
  /// [b] destination buffer
  /// [off] offset at which to start storing characters
  /// [len] maximum number of characters to read
  /// Returns the number of bytes actually read or -1 in case of EOF.
  int readBytes(Uint8List b, int off, int len) {
    if (len == 0) {
      return 0;
    }
    var count = 0;
    if (_isBack && len > 0) {
      _isBack = false;
      b[off++] = _back;
      --len;
      count++;
    }
    if (len > 0) {
      final byteSourceCount =
          _byteSource.getRange(_byteSourcePosition, b, off, len);
      if (byteSourceCount > 0) {
        count += byteSourceCount;
        _byteSourcePosition += byteSourceCount;
      }
    }
    if (count == 0) {
      return -1;
    }
    return count;
  }

  /// Reads bytes to the buffer.
  ///
  /// This method will try to read as many bytes as the buffer can hold.
  int readBuffer(Uint8List b) {
    return readBytes(b, 0, b.length);
  }

  /// Reads bytes to fill the buffer completely.
  void readFully(Uint8List b) {
    readFullyRange(b, 0, b.length);
  }

  /// Reads bytes to fill the buffer completely within the specified range.
  void readFullyRange(Uint8List b, int off, int len) {
    var n = 0;
    do {
      final count = readBytes(b, off + n, len - n);
      if (count < 0) {
        throw EndOfStreamException();
      }
      n += count;
    } while (n < len);
  }

  /// Make an attempt to skip the specified amount of bytes in source.
  ///
  /// However it may skip less amount of bytes. Possibly zero.
  int skip(int n) {
    if (n <= 0) {
      return 0;
    }
    var adj = 0;
    if (_isBack) {
      _isBack = false;
      if (n == 1) {
        return 1;
      } else {
        --n;
        adj = 1;
      }
    }
    final pos = getPosition();
    final len = length();
    var newpos = pos + n;
    if (newpos > len) {
      newpos = len;
    }
    seek(newpos);
    return newpos - pos + adj;
  }

  /// Skips the specified number of bytes.
  int skipBytes(int n) {
    return skip(n);
  }

  /// Closes the underlying source.
  void close() {
    _isBack = false;
    _byteSource.close();
  }

  /// Gets the total amount of bytes in the source.
  int length() {
    return _byteSource.length();
  }

  /// Sets the current position in the source to the specified index.
  void seek(int pos) {
    _byteSourcePosition = pos;
    _isBack = false;
  }

  /// Gets the current position of the source considering the pushed byte.
  int getPosition() {
    return _byteSourcePosition - (_isBack ? 1 : 0);
  }

  /// Reads a boolean.
  bool readBoolean() {
    final ch = read();
    if (ch < 0) {
      throw EndOfStreamException();
    }
    return ch != 0;
  }

  /// Reads a signed byte.
  int readByte() {
    final ch = read();
    if (ch < 0) {
      throw EndOfStreamException();
    }
    return ch;
  }

  /// Reads an unsigned byte.
  int readUnsignedByte() {
    final ch = read();
    if (ch < 0) {
      throw EndOfStreamException();
    }
    return ch;
  }

  /// Reads a signed 16-bit number (big-endian).
  int readShort() {
    final ch1 = read();
    final ch2 = read();
    if ((ch1 | ch2) < 0) {
      throw EndOfStreamException();
    }
    var result = (ch1 << 8) + ch2;
    // Sign extend
    if (result >= 0x8000) {
      result -= 0x10000;
    }
    return result;
  }

  /// Reads a signed 16-bit number (little-endian).
  int readShortLE() {
    final ch1 = read();
    final ch2 = read();
    if ((ch1 | ch2) < 0) {
      throw EndOfStreamException();
    }
    var result = (ch2 << 8) + ch1;
    // Sign extend
    if (result >= 0x8000) {
      result -= 0x10000;
    }
    return result;
  }

  /// Reads an unsigned 16-bit number (big-endian).
  int readUnsignedShort() {
    final ch1 = read();
    final ch2 = read();
    if ((ch1 | ch2) < 0) {
      throw EndOfStreamException();
    }
    return (ch1 << 8) + ch2;
  }

  /// Reads an unsigned 16-bit number (little-endian).
  int readUnsignedShortLE() {
    final ch1 = read();
    final ch2 = read();
    if ((ch1 | ch2) < 0) {
      throw EndOfStreamException();
    }
    return (ch2 << 8) + ch1;
  }

  /// Reads a Unicode character (big-endian).
  int readChar() {
    final ch1 = read();
    final ch2 = read();
    if ((ch1 | ch2) < 0) {
      throw EndOfStreamException();
    }
    return (ch1 << 8) + ch2;
  }

  /// Reads a Unicode character (little-endian).
  int readCharLE() {
    final ch1 = read();
    final ch2 = read();
    if ((ch1 | ch2) < 0) {
      throw EndOfStreamException();
    }
    return (ch2 << 8) + ch1;
  }

  /// Reads a signed 32-bit integer (big-endian).
  int readInt() {
    final ch1 = read();
    final ch2 = read();
    final ch3 = read();
    final ch4 = read();
    if ((ch1 | ch2 | ch3 | ch4) < 0) {
      throw EndOfStreamException();
    }
    return (ch1 << 24) + (ch2 << 16) + (ch3 << 8) + ch4;
  }

  /// Reads a signed 32-bit integer (little-endian).
  int readIntLE() {
    final ch1 = read();
    final ch2 = read();
    final ch3 = read();
    final ch4 = read();
    if ((ch1 | ch2 | ch3 | ch4) < 0) {
      throw EndOfStreamException();
    }
    return (ch4 << 24) + (ch3 << 16) + (ch2 << 8) + ch1;
  }

  /// Reads an unsigned 32-bit integer (big-endian).
  int readUnsignedInt() {
    final ch1 = read();
    final ch2 = read();
    final ch3 = read();
    final ch4 = read();
    if ((ch1 | ch2 | ch3 | ch4) < 0) {
      throw EndOfStreamException();
    }
    return (ch1 << 24) + (ch2 << 16) + (ch3 << 8) + ch4;
  }

  /// Reads an unsigned 32-bit integer (little-endian).
  int readUnsignedIntLE() {
    final ch1 = read();
    final ch2 = read();
    final ch3 = read();
    final ch4 = read();
    if ((ch1 | ch2 | ch3 | ch4) < 0) {
      throw EndOfStreamException();
    }
    return (ch4 << 24) + (ch3 << 16) + (ch2 << 8) + ch1;
  }

  /// Reads a signed 64-bit integer (big-endian).
  int readLong() {
    return (readInt() << 32) + (readInt() & 0xFFFFFFFF);
  }

  /// Reads a signed 64-bit integer (little-endian).
  int readLongLE() {
    final i1 = readIntLE();
    final i2 = readIntLE();
    return (i2 << 32) + (i1 & 0xFFFFFFFF);
  }

  /// Reads a 32-bit float (big-endian).
  double readFloat() {
    final bytes = Uint8List(4);
    readFully(bytes);
    return (ByteData.view(bytes.buffer)).getFloat32(0);
  }

  /// Reads a 32-bit float (little-endian).
  double readFloatLE() {
    final bytes = Uint8List(4);
    readFully(bytes);
    return (ByteData.view(bytes.buffer)).getFloat32(0, Endian.little);
  }

  /// Reads a 64-bit double (big-endian).
  double readDouble() {
    final bytes = Uint8List(8);
    readFully(bytes);
    return (ByteData.view(bytes.buffer)).getFloat64(0);
  }

  /// Reads a 64-bit double (little-endian).
  double readDoubleLE() {
    final bytes = Uint8List(8);
    readFully(bytes);
    return (ByteData.view(bytes.buffer)).getFloat64(0, Endian.little);
  }

  /// Reads a line of text.
  String? readLine() {
    final input = StringBuffer();
    var c = -1;
    var eol = false;
    while (!eol) {
      c = read();
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
        default:
          input.writeCharCode(c);
          break;
      }
    }
    if (c == -1 && input.isEmpty) {
      return null;
    }
    return input.toString();
  }

  /// Reads a String from the source as bytes using the given encoding.
  String readString(int length, [Encoding encoding = latin1]) {
    final buf = Uint8List(length);
    readFully(buf);
    return encoding.decode(buf);
  }

  /// Ensures the byte source is thread safe.
  void _ensureByteSourceIsThreadSafe() {
    if (_byteSource is! ThreadSafeRandomAccessSource) {
      _byteSource = ThreadSafeRandomAccessSource(_byteSource);
    }
  }
}
