import 'dart:typed_data';

import 'i_random_access_source.dart';

/// A thread-safe wrapper for RandomAccessSource.
///
/// Note: In Dart single-isolate context, this class doesn't need actual locking.
/// However, it maintains the same interface as the C# version for compatibility.
/// If used across isolates, appropriate synchronization would be needed.
class ThreadSafeRandomAccessSource implements IRandomAccessSource {
  /// The underlying source.
  final IRandomAccessSource _source;

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
    _source.close();
  }
}
