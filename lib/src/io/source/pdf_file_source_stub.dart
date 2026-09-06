import 'dart:typed_data';
import 'pdf_byte_source.dart';

class PdfFileSource implements PdfByteSource {
  PdfFileSource.open(String path,
      {int blockSize = 262144, int maxBlocks = 32}) {
    throw UnsupportedError(
        'File-backed PDF input requires the Dart VM. Use PdfMemorySource on the web.');
  }
  @override
  int get length => throw StateError('File source was not opened.');
  int get cachedBytes => 0;
  int get bytesRead => 0;
  @override
  int byteAt(int offset) => throw StateError('File source was not opened.');
  @override
  int readInto(int position, Uint8List target, int offset, int count) =>
      throw StateError('File source was not opened.');
  @override
  void close() {}
}
