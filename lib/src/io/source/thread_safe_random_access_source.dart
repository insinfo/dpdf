import 'dart:typed_data';

import 'random_access_source.dart';

/// A forwarding wrapper for a synchronous random-access source.
///
/// This wrapper does not provide locking or share a source between isolates.
/// Each worker must own its source. The historical class name is retained for
/// source compatibility.
class ThreadSafeRandomAccessSource implements RandomAccessSource {
  /// The underlying source.
  final RandomAccessSource _source;

  /// Constructs a new ThreadSafeRandomAccessSource.
  ThreadSafeRandomAccessSource(this._source);

  @override
  int get(int position) {
    // In single-isolate Dart, no locking is needed
    return _source.get(position);
  }

  @override
  int getRange(int position, Uint8List bytes, int off, int len) {
    // In single-isolate Dart, no locking is needed
    return _source.getRange(position, bytes, off, len);
  }

  @override
  int length() {
    // In single-isolate Dart, no locking is needed
    return _source.length();
  }

  @override
  void close() {
    // In single-isolate Dart, no locking is needed
    return _source.close();
  }
}
