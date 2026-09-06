import 'dart:typed_data';

/// Positional byte input. Reads do not change a shared cursor.
/// Implementations must return -1 at EOF, and 0 for a zero-length read.
abstract class PdfByteSource {
  int get length;
  int byteAt(int offset);
  int readInto(int position, Uint8List target, int offset, int count);
  void close();
}

class PdfMemorySource implements PdfByteSource {
  final Uint8List bytes;
  PdfMemorySource(this.bytes);
  @override
  int get length => bytes.length;
  @override
  int byteAt(int offset) {
    if (offset < 0) throw RangeError.value(offset);
    return offset >= length ? -1 : bytes[offset];
  }

  @override
  int readInto(int position, Uint8List target, int offset, int count) {
    RangeError.checkNotNegative(position, 'position');
    RangeError.checkValidRange(offset, offset + count, target.length);
    if (count == 0) return 0;
    if (position >= length) return -1;
    final size = count < length - position ? count : length - position;
    target.setRange(offset, offset + size, bytes, position);
    return size;
  }

  @override
  void close() {}
}
