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

import 'pdf_object.dart';

/// Abstract base class for PDF primitive objects.
///
/// Primitive objects have raw byte content that can be generated lazily.
abstract class PdfPrimitiveObject extends PdfObject {
  /// The raw byte content of this object.
  Uint8List? _content;

  /// If true, this object cannot be made indirect.
  bool _directOnly = false;

  /// Creates an empty primitive object.
  PdfPrimitiveObject();

  /// Creates a primitive object that can only be direct (not indirect).
  PdfPrimitiveObject.directOnly(bool directOnly) {
    _directOnly = directOnly;
  }

  /// Creates a primitive object with the given content.
  PdfPrimitiveObject.withContent(Uint8List content) {
    _content = content;
  }

  /// Gets the internal content, generating it if necessary.
  Uint8List? getInternalContent() {
    if (_content == null) {
      generateContent();
    }
    return _content;
  }

  /// Sets the internal content.
  void setContent(Uint8List? content) {
    _content = content;
  }

  /// Returns true if content has been set or generated.
  bool hasContent() {
    return _content != null;
  }

  /// Generates the byte content for this object.
  ///
  /// Subclasses must implement this to produce their byte representation.
  void generateContent();

  /// Whether this object is direct-only (cannot be indirect).
  bool get isDirectOnly => _directOnly;

  /// Compares the content of two primitive objects.
  ///
  /// Returns negative if this < other, zero if equal, positive if this > other.
  int compareContent(PdfPrimitiveObject other) {
    final myContent = getInternalContent();
    final otherContent = other.getInternalContent();

    if (myContent == null && otherContent == null) return 0;
    if (myContent == null) return -1;
    if (otherContent == null) return 1;

    final minLen = myContent.length < otherContent.length
        ? myContent.length
        : otherContent.length;

    for (var i = 0; i < minLen; i++) {
      final diff = myContent[i] - otherContent[i];
      if (diff != 0) return diff > 0 ? 1 : -1;
    }

    return myContent.length.compareTo(otherContent.length);
  }

  @override
  void copyContent(PdfObject from, [dynamic document]) {
    super.copyContent(from, document);
    if (from is PdfPrimitiveObject && from._content != null) {
      _content = Uint8List.fromList(from._content!);
    }
  }
}
