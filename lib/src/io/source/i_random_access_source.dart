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

/// Represents an abstract source that bytes can be read from.
///
/// This class forms the foundation for all byte input in iText.
/// Implementations do not keep track of a current 'position', but rather
/// provide absolute get methods. Tracking position should be handled in
/// classes that use RandomAccessSource internally (via composition).
abstract class IRandomAccessSource {
  /// Gets a byte at the specified position.
  ///
  /// [position] byte position
  /// Returns the byte, or -1 if EOF is reached.
  int get(int position);

  /// Read an array of bytes of specified length from the specified position
  /// of source to the buffer applying the offset.
  ///
  /// If the number of bytes requested cannot be read, all the possible bytes
  /// will be read to the buffer, and the number of actually read bytes will
  /// be returned.
  ///
  /// [position] the position in the RandomAccessSource to read from
  /// [bytes] output buffer
  /// [off] offset into the output buffer where results will be placed
  /// [len] the number of bytes to read
  /// Returns the number of bytes actually read, or -1 if the file is at EOF.
  int getRange(int position, Uint8List bytes, int off, int len);

  /// Gets the length of the source.
  ///
  /// Returns the length of this source.
  int length();

  /// Closes this source.
  ///
  /// The underlying data structure or source (if any) will also be closed.
  void close();
}
