import 'dart:io';
import 'dart:typed_data';
import 'pdf_byte_source.dart';

/// Read-only block cache with an explicit memory ceiling. The caller must keep
/// the file unchanged while it is open and close the reader when finished.
class PdfFileSource implements PdfByteSource {
  final RandomAccessFile _file;
  @override
  final int length;
  final int blockSize;
  final int maxBlocks;
  final _cache = <int, Uint8List>{};
  int _lastBlockNumber = -1;
  Uint8List? _lastBlock;
  bool _closed = false;
  int _bytesRead = 0;
  int get bytesRead => _bytesRead;
  int get cachedBytes =>
      _cache.values.fold(0, (sum, block) => sum + block.length);
  PdfFileSource._(this._file, this.length, this.blockSize, this.maxBlocks);
  factory PdfFileSource.open(String path,
      {int blockSize = 262144, int maxBlocks = 32}) {
    RangeError.checkValueInInterval(
        blockSize, 256, 16 * 1024 * 1024, 'blockSize');
    RangeError.checkValueInInterval(maxBlocks, 1, 4096, 'maxBlocks');
    final file = File(path).openSync();
    try {
      return PdfFileSource._(file, file.lengthSync(), blockSize, maxBlocks);
    } catch (_) {
      file.closeSync();
      rethrow;
    }
  }
  void _check() {
    if (_closed) throw StateError('PDF file source is closed.');
  }

  Uint8List _block(int number) {
    _check();
    if (number == _lastBlockNumber) return _lastBlock!;
    final previous = _cache.remove(number);
    if (previous != null) {
      _cache[number] = previous;
      _lastBlockNumber = number;
      _lastBlock = previous;
      return previous;
    }
    final start = number * blockSize;
    final size = length - start < blockSize ? length - start : blockSize;
    final bytes = Uint8List(size);
    _file.setPositionSync(start);
    var received = 0;
    while (received < size) {
      final count = _file.readIntoSync(bytes, received, size);
      if (count == 0) {
        throw FileSystemException(
            'PDF file changed or was truncated while reading.');
      }
      received += count;
    }
    _bytesRead += received;
    if (_cache.length >= maxBlocks) _cache.remove(_cache.keys.first);
    _cache[number] = bytes;
    _lastBlockNumber = number;
    _lastBlock = bytes;
    return bytes;
  }

  @override
  int byteAt(int offset) {
    _check();
    RangeError.checkNotNegative(offset, 'offset');
    if (offset >= length) return -1;
    return _block(offset ~/ blockSize)[offset % blockSize];
  }

  @override
  int readInto(int position, Uint8List target, int offset, int count) {
    _check();
    RangeError.checkNotNegative(position, 'position');
    RangeError.checkValidRange(offset, offset + count, target.length);
    if (count == 0) return 0;
    if (position >= length) return -1;
    final total = count < length - position ? count : length - position;
    var done = 0;
    while (done < total) {
      final absolute = position + done;
      final block = _block(absolute ~/ blockSize);
      final local = absolute % blockSize;
      final amount = total - done < block.length - local
          ? total - done
          : block.length - local;
      target.setRange(offset + done, offset + done + amount, block, local);
      done += amount;
    }
    return total;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _cache.clear();
    _lastBlock = null;
    _lastBlockNumber = -1;
    _file.closeSync();
  }
}
