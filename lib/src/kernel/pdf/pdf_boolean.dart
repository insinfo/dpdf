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

import 'pdf_object.dart';

/// Represents a PDF boolean object.
class PdfBoolean extends PdfObject {
  /// Singleton for true.
  static final PdfBoolean pdfTrue = PdfBoolean._internal(true);

  /// Singleton for false.
  static final PdfBoolean pdfFalse = PdfBoolean._internal(false);

  /// The boolean value.
  final bool _value;

  /// Private constructor for singletons.
  PdfBoolean._internal(this._value);

  /// Creates a PdfBoolean with the given value.
  ///
  /// Returns singleton instances for true and false.
  factory PdfBoolean(bool value) {
    return value ? pdfTrue : pdfFalse;
  }

  @override
  int getObjectType() => PdfObjectType.boolean;

  @override
  PdfObject clone() {
    return PdfBoolean(_value);
  }

  @override
  PdfObject newInstance() {
    return PdfBoolean(false);
  }

  /// Gets the boolean value.
  bool getValue() => _value;

  @override
  String toString() {
    return _value ? 'true' : 'false';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfBoolean) return false;
    return _value == other._value;
  }

  @override
  int get hashCode => _value.hashCode;
}
