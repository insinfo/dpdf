import 'dart:typed_data';

import 'random_access_source.dart';

/// A thread-safe wrapper for RandomAccessSource.
///
/// Note: In Dart single-isolate context, this class doesn't need actual locking.
/// However, it maintains the same interface as the C# version for compatibility.
/// If used across isolates, appropriate synchronization would be needed.
class CraftThreadSafeRandomAccessSource implements CraftRandomAccessSource {
  /// The underlying source.
  final CraftRandomAccessSource _source;

  /// Constructs a new ThreadSafeRandomAccessSource.
  CraftThreadSafeRandomAccessSource(this._source);

  @override
  Future<int> get(int position) {
    // In single-isolate Dart, no locking is needed
    return _source.get(position);
  }

  @override
  Future<int> getRange(int position, Uint8List bytes, int off, int len) {
    // In single-isolate Dart, no locking is needed
    return _source.getRange(position, bytes, off, len);
  }

  @override
  Future<int> length() {
    // In single-isolate Dart, no locking is needed
    return _source.length();
  }

  @override
  Future<void> close() {
    // In single-isolate Dart, no locking is needed
    return _source.close();
  }
}
