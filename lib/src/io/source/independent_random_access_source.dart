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
