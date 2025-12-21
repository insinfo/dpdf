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
