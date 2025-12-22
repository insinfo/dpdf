import 'dart:typed_data';
import 'dart:io';

class RandomAccessFileOrArray {
  final Uint8List _data;
  int _position = 0;
  int? _back;

  RandomAccessFileOrArray(Uint8List data) : _data = data;

  factory RandomAccessFileOrArray.fromFile(File file) {
    return RandomAccessFileOrArray(file.readAsBytesSync());
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
      int remaining = _data.length - _position;
      int toRead = len < remaining ? len : remaining;
      if (toRead <= 0) return count == 0 ? -1 : count;

      for (int i = 0; i < toRead; i++) {
        buffer[offset + i] = _data[_position + i];
      }
      _position += toRead;
      count += toRead;
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

  int length() => _data.length;

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
    if (_position >= _data.length) return -1;
    return _data[_position++];
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
    int remaining = _data.length - _position;
    if (n > remaining) n = remaining;
    _position += n;
    _back = null;
  }

  String readString(int length, String encoding) {
    List<int> buf = List.filled(length, 0);
    readFully(Uint8List.fromList(buf)); // Wait, readFully takes Uint8List
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
    if (_position >= _data.length) return -1;
    return _data[_position];
  }

  RandomAccessFileOrArray createView() {
    return RandomAccessFileOrArray(_data);
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

  void close() {
    // No-op for byte array
  }
}
