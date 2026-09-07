import '../../platform/int64.dart';
import 'pdf_byte_source.dart';
import 'dart:typed_data';
import '../../platform/io.dart';

class RandomAccessFileOrArray {
  final PdfByteSource _source;
  final bool _ownsSource;
  int _position = 0;
  int? _back;

  RandomAccessFileOrArray(Uint8List data)
      : _source = PdfMemorySource(data),
        _ownsSource = true;

  RandomAccessFileOrArray.fromSource(this._source, {bool ownsSource = true})
      : _ownsSource = ownsSource;

  factory RandomAccessFileOrArray.fromFile(File file) {
    return RandomAccessFileOrArray(file.readAsBytesSync());
  }

  /// Explicit materialization. Streaming reader paths use positional reads.
  Uint8List getBytes() {
    if (_source is PdfMemorySource) return _source.bytes;
    final bytes = Uint8List(_source.length);
    var offset = 0;
    while (offset < bytes.length) {
      final count =
          _source.readInto(offset, bytes, offset, bytes.length - offset);
      if (count <= 0) {
        throw FormatException('Input ended while materializing bytes.');
      }
      offset += count;
    }
    return bytes;
  }

  void readFully(Uint8List bytes) {
    readFullyInto(bytes, 0, bytes.length);
  }

  void readFullyInto(Uint8List bytes, int offset, int length) {
    int len = length;
    int currentOffset = offset;
    while (len > 0) {
      int count = readBufferInto(bytes, currentOffset, len);
      if (count <= 0) throw Exception("EOF");
      currentOffset += count;
      len -= count;
    }
  }

  int readBufferInto(List<int> buffer, int offset, int length) {
    int len = length;
    if (len == 0) return 0;

    int count = 0;
    if (_back != null && len > 0) {
      buffer[offset++] = _back!;
      len--;
      count++;
      _back = null;
    }

    if (len > 0) {
      int remaining = _source.length - _position;
      int toRead = len < remaining ? len : remaining;
      if (toRead <= 0) return count == 0 ? -1 : count;

      final target = buffer is Uint8List ? buffer : Uint8List(toRead);
      final received = _source.readInto(
          _position, target, buffer is Uint8List ? offset : 0, toRead);
      if (received <= 0) return count == 0 ? -1 : count;
      if (buffer is! Uint8List) {
        buffer.setRange(offset, offset + received, target);
      }
      _position += received;
      count += received;
    }
    return count;
  }

  int peekBuffer(Uint8List buffer) {
    int oldPos = _position;
    int? oldBack = _back;
    int count = readBuffer(buffer);
    _position = oldPos;
    _back = oldBack;
    return count;
  }

  int length() => _source.length;

  void seek(int pos) {
    _position = pos;
    _back = null;
  }

  int getPosition() {
    return _position - (_back != null ? 1 : 0);
  }

  void pushBack(int b) {
    _back = b;
  }

  int read() {
    if (_back != null) {
      int b = _back!;
      _back = null;
      return b;
    }
    if (_position >= _source.length) return -1;
    return _source.byteAt(_position++);
  }

  int readByte() {
    int ch = read();
    if (ch < 0) throw Exception("End of stream");
    return ch;
  }

  int readUnsignedByte() {
    return readByte() & 0xFF;
  }

  int readShort() {
    int ch1 = read();
    int ch2 = read();
    if ((ch1 | ch2) < 0) throw Exception("End of stream");
    var val = (ch1 << 8) + ch2;
    // Interpret as signed 16-bit
    if (val > 32767) val -= 65536;
    return val;
  }

  int readUnsignedShort() {
    int ch1 = read();
    int ch2 = read();
    if ((ch1 | ch2) < 0) throw Exception("End of stream");
    return (ch1 << 8) + ch2;
  }

  void skipBytes(int n) {
    if (n <= 0) return;
    int remaining = _source.length - _position;
    if (n > remaining) n = remaining;
    _position += n;
    _back = null;
  }

  String readString(int length, String encoding) {
    final buf = Uint8List(length);
    readFully(buf); // Wait, readFully takes Uint8List
    // Or just readBuffer
    // readBuffer(buf);
    // Actually I can just read bytes.
    if (encoding.toUpperCase() == "UTF-16BE") {
      // Manual utf-16be decode or use generic
      // Dart does not have built-in UTF-16BE decoder easily accessible?
      // It has UTF-16 but usually LE.
      // Let's do simple char construction
      StringBuffer sb = StringBuffer();
      for (int i = 0; i < length; i += 2) {
        int b1 = buf[i];
        int b2 = buf[i + 1]; // check bounds
        sb.writeCharCode((b1 << 8) + b2);
      }
      return sb.toString();
    }
    if (encoding.toUpperCase() == "ISO-8859-1") {
      return String.fromCharCodes(buf);
    }
    try {
      // Fallback or implementation
      return String.fromCharCodes(buf);
    } catch (e) {
      return "";
    }
  }

  int readInt() {
    int ch1 = read();
    int ch2 = read();
    int ch3 = read();
    int ch4 = read();
    if ((ch1 | ch2 | ch3 | ch4) < 0) throw Exception("End of stream");
    return ((ch1 << 24) + (ch2 << 16) + (ch3 << 8) + ch4);
  }

  int readBuffer(List<int> buffer, [int offset = 0, int? length]) {
    return readBufferInto(buffer, offset, length ?? buffer.length);
  }

  int peek() {
    if (_back != null) return _back!;
    if (_position >= _source.length) return -1;
    return _source.byteAt(_position);
  }

  RandomAccessFileOrArray createView() {
    return RandomAccessFileOrArray.fromSource(_source, ownsSource: false);
  }

  String? readLine() {
    StringBuffer sb = StringBuffer();
    int c = -1;
    bool eol = false;
    while (!eol) {
      c = read();
      switch (c) {
        case -1:
        case 10: // \n
          eol = true;
          break;
        case 13: // \r
          eol = true;
          int cur = getPosition();
          if (read() != 10) {
            seek(cur);
          }
          break;
        default:
          sb.writeCharCode(c);
          break;
      }
    }
    if (c == -1 && sb.length == 0) return null;
    return sb.toString();
  }

  int readShortLE() {
    int ch1 = read();
    int ch2 = read();
    if ((ch1 | ch2) < 0) throw Exception("End of stream");
    var val = (ch2 << 8) + ch1;
    if (val > 32767) val -= 65536;
    return val;
  }

  void close() {
    if (_ownsSource) _source.close();
  }

  int readUnsignedShortLE() {
    int ch1 = read();
    int ch2 = read();
    if ((ch1 | ch2) < 0) throw Exception("End of stream");
    return (ch2 << 8) + ch1;
  }

  int readIntLE() {
    int ch1 = read();
    int ch2 = read();
    int ch3 = read();
    int ch4 = read();
    if ((ch1 | ch2 | ch3 | ch4) < 0) throw Exception("End of stream");
    int val = (ch4 << 24) + (ch3 << 16) + (ch2 << 8) + ch1;
    // Interpret as signed 32-bit
    return val.toSigned(32);
  }

  int readUnsignedInt() {
    int ch1 = read();
    int ch2 = read();
    int ch3 = read();
    int ch4 = read();
    if ((ch1 | ch2 | ch3 | ch4) < 0) throw Exception("End of stream");
    return ((ch1 << 24) + (ch2 << 16) + (ch3 << 8) + ch4);
  }

  int readUnsignedIntLE() {
    int ch1 = read();
    int ch2 = read();
    int ch3 = read();
    int ch4 = read();
    if ((ch1 | ch2 | ch3 | ch4) < 0) throw Exception("End of stream");
    return ((ch4 << 24) + (ch3 << 16) + (ch2 << 8) + ch1);
  }

  /// Reads a signed eight-byte integer without losing precision on JavaScript.
  BigInt readBigInt64({Endian endian = Endian.big}) {
    final bytes = Uint8List(8);
    readFully(bytes);
    return signedWord64(ByteData.sublistView(bytes), 0, endian);
  }

  int _exactInteger64(Endian endian) {
    final value = readBigInt64(endian: endian);
    final integer = value.toInt();
    if (BigInt.from(integer) != value) {
      throw RangeError('The integer requires readBigInt64 on this target.');
    }
    return integer;
  }

  int readLong() => _exactInteger64(Endian.big);

  int readLong8() => _exactInteger64(Endian.big);

  int readLongLE() => _exactInteger64(Endian.little);

  double readFloat() {
    int i = readInt(); // Gets signed 32-bit int
    // Convert to float
    var buffer = ByteData(4);
    buffer.setInt32(0, i, Endian.big);
    return buffer.getFloat32(0, Endian.big);
  }

  double readFloatLE() {
    int i = readIntLE();
    var buffer = ByteData(4);
    buffer.setInt32(
        0, i, Endian.little); // Wait, i is already constructed as LE int?
    // No, readIntLE constructs the int value.
    // ByteData wraps raw bytes?
    // If I constructed `val` from bytes using (ch4 << 24) etc, I have the INTEGER value for LE.
    // If I put that integer as Little Endian int32 into ByteData, the underlying bytes will be [ch1, ch2, ch3, ch4].
    // Then getting float32 with Little Endian should work.
    return buffer.getFloat32(0, Endian.little);
  }

  double _readFloating64(Endian endian) {
    final bytes = Uint8List(8);
    readFully(bytes);
    return ByteData.sublistView(bytes).getFloat64(0, endian);
  }

  double readDouble() => _readFloating64(Endian.big);

  double readDoubleLE() => _readFloating64(Endian.little);

  void skip(int n) {
    skipBytes(n);
  }
}
