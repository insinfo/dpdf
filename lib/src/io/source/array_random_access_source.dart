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
  Future<int> get(int offset) async {
    if (_array == null) {
      throw StateError(IoExceptionMessageConstant.alreadyClosed);
    }
    if (offset >= _array!.length) {
      return -1;
    }
    return _array![offset] & 0xFF;
  }

  @override
  Future<int> getRange(int offset, Uint8List bytes, int off, int len) async {
    if (_array == null) {
      throw StateError(IoExceptionMessageConstant.alreadyClosed);
    }
    if (offset >= _array!.length) {
      return -1;
    }
    var actualLen = len;
    if (offset + actualLen > _array!.length) {
      actualLen = _array!.length - offset;
    }
    for (var i = 0; i < actualLen; i++) {
      bytes[off + i] = _array![offset + i];
    }
    return actualLen;
  }

  @override
  Future<int> length() async {
    if (_array == null) {
      throw StateError(IoExceptionMessageConstant.alreadyClosed);
    }
    return _array!.length;
  }

  @override
  Future<void> close() async {
    _array = null;
  }
}
