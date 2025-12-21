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

import 'dart:convert';
import 'dart:typed_data';

import 'pdf_object.dart';
import 'pdf_primitive_object.dart';

/// Represents a PDF literal object.
///
/// A literal is a sequence of bytes that is passed through unchanged.
/// This is used for raw PDF content that should not be interpreted.
class PdfLiteral extends PdfPrimitiveObject {
  /// Position in the file where this literal was found.
  int _position = 0;

  /// Creates a PdfLiteral with the given byte content.
  PdfLiteral.fromBytes(Uint8List content) : super.directOnly(true) {
    setContent(content);
  }

  /// Creates a PdfLiteral with a fixed size filled with spaces.
  PdfLiteral.withSize(int size) : super.directOnly(true) {
    final content = Uint8List(size);
    content.fillRange(0, size, 0x20); // Fill with spaces
    setContent(content);
  }

  /// Creates a PdfLiteral from a string.
  PdfLiteral(String content) : super.directOnly(true) {
    setContent(Uint8List.fromList(latin1.encode(content)));
  }

  /// Private constructor for cloning.
  PdfLiteral._empty() : super.directOnly(true);

  @override
  int getObjectType() => PdfObjectType.literal;

  @override
  void generateContent() {
    // Content is always set directly, never generated
  }

  @override
  PdfObject clone() {
    final cloned = PdfLiteral._empty();
    final content = getInternalContent();
    if (content != null) {
      cloned.setContent(Uint8List.fromList(content));
    }
    cloned._position = _position;
    return cloned;
  }

  @override
  PdfObject newInstance() {
    return PdfLiteral._empty();
  }

  /// Gets the position in the file where this literal was found.
  int getPosition() => _position;

  /// Sets the position.
  void setPosition(int position) {
    _position = position;
  }

  /// Gets the number of bytes in this literal.
  int getBytesCount() {
    final content = getInternalContent();
    return content?.length ?? 0;
  }

  @override
  String toString() {
    final content = getInternalContent();
    if (content != null) {
      return latin1.decode(content);
    }
    return '';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfLiteral) return false;

    final myContent = getInternalContent();
    final otherContent = other.getInternalContent();

    if (myContent == null && otherContent == null) return true;
    if (myContent == null || otherContent == null) return false;
    if (myContent.length != otherContent.length) return false;

    for (var i = 0; i < myContent.length; i++) {
      if (myContent[i] != otherContent[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    final content = getInternalContent();
    if (content == null) return 0;

    // Use FNV-1a hash for byte arrays
    var hash = 0x811c9dc5;
    for (final byte in content) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}
