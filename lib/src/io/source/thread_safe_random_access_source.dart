/*
 * This file is part of the iText (R) project.
 * Copyright (c) 1998-2025 Apryse Group NV
 * Authors: Apryse Software.
 *
 * This program is offered under a commercial and under the AGPL license.
 * For commercial licensing, contact us at https://itextpdf.com/sales.
 * For AGPL licensing, see below.
 *
 * AGPL licensing:
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

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
