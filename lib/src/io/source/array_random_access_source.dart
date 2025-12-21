import 'dart:typed_data';

import '../exceptions/io_exception_message_constant.dart';
import 'i_random_access_source.dart';

/// A RandomAccessSource that is based on an underlying byte array.
class ArrayRandomAccessSource implements IRandomAccessSource {
  Uint8List? _array;

  /// Creates a new ArrayRandomAccessSource from an array.
  ///
  /// [array] the underlying byte array
  ArrayRandomAccessSource(Uint8List array) {
    _array = array;
  }

  @override
  int get(int offset) {
    if (_array == null) {
      throw StateError(IoExceptionMessageConstant.alreadyClosed);
    }
    if (offset >= _array!.length) {
      return -1;
    }
    return _array![offset] & 0xFF;
  }

  @override
  int getRange(int offset, Uint8List bytes, int off, int len) {
    if (_array == null) {
      throw StateError(IoExceptionMessageConstant.alreadyClosed);
    }
    if (offset >= _array!.length) {
      return -1;
    }
    if (offset + len > _array!.length) {
      len = _array!.length - offset;
    }
    for (var i = 0; i < len; i++) {
      bytes[off + i] = _array![offset + i];
    }
    return len;
  }

  @override
  int length() {
    if (_array == null) {
      throw StateError(IoExceptionMessageConstant.alreadyClosed);
    }
    return _array!.length;
  }

  @override
  void close() {
    _array = null;
  }
}
