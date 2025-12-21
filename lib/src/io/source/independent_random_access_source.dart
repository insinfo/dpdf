import 'dart:typed_data';

import 'i_random_access_source.dart';

/// A RandomAccessSource that wraps another RandomAccessSource but does not propagate close().
///
/// This is useful when passing a RandomAccessSource to a method that would
/// normally close the source.
class IndependentRandomAccessSource implements IRandomAccessSource {
  /// The underlying source.
  final IRandomAccessSource _source;

  /// Constructs a new IndependentRandomAccessSource object.
  IndependentRandomAccessSource(this._source);

  @override
  int get(int position) {
    return _source.get(position);
  }

  @override
  int getRange(int position, Uint8List bytes, int off, int len) {
    return _source.getRange(position, bytes, off, len);
  }

  @override
  int length() {
    return _source.length();
  }

  /// Does nothing - the underlying source is not closed.
  @override
  void close() {
    // do not close the source
  }
}
