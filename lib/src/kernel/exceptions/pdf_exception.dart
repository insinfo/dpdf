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

import '../../commons/exceptions/itext_exception.dart';

/// Exception thrown when a PDF processing error occurs in the kernel module.
class PdfException extends ITextException {
  /// Object that was being processed when the exception occurred.
  final Object? pdfObject;

  /// Creates a PdfException with the specified message.
  PdfException(String message, {Object? cause, this.pdfObject})
      : super(message, cause);

  /// Creates a PdfException with message parameters.
  ///
  /// The [message] can contain placeholders like {0}, {1}, etc.
  /// that will be replaced with the provided [params].
  factory PdfException.withParams(String message, List<Object?> params,
      {Object? cause, Object? pdfObject}) {
    var formattedMessage = message;
    for (var i = 0; i < params.length; i++) {
      formattedMessage =
          formattedMessage.replaceAll('{$i}', params[i]?.toString() ?? 'null');
    }
    return PdfException(formattedMessage, cause: cause, pdfObject: pdfObject);
  }

  /// Sets the message parameters and returns a new exception.
  ///
  /// Allows fluent API usage:
  /// ```dart
  /// throw PdfException(KernelExceptionMessageConstant.invalidIndirectReference)
  ///     .setMessageParams([5, 0]);
  /// ```
  PdfException setMessageParams(List<Object?> params) {
    var formattedMessage = message;
    for (var i = 0; i < params.length; i++) {
      formattedMessage =
          formattedMessage.replaceAll('{$i}', params[i]?.toString() ?? 'null');
    }
    return PdfException(formattedMessage, cause: cause, pdfObject: pdfObject);
  }

  @override
  String toString() {
    final buffer = StringBuffer('PdfException: $message');
    if (pdfObject != null) {
      buffer.write('\nObject: $pdfObject');
    }
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}

/// Exception thrown when a bad password is provided for an encrypted PDF.
class BadPasswordException extends PdfException {
  BadPasswordException(String message, {Object? cause})
      : super(message, cause: cause);
}

/// Exception thrown when the PDF document is encrypted but no password was provided.
class EncryptedDocumentException extends PdfException {
  EncryptedDocumentException(String message, {Object? cause})
      : super(message, cause: cause);
}

/// Exception thrown when an invalid PDF structure is encountered.
class InvalidPdfException extends PdfException {
  InvalidPdfException(String message, {Object? cause, Object? pdfObject})
      : super(message, cause: cause, pdfObject: pdfObject);
}

/// Exception thrown for XRef table/stream errors.
class XrefException extends PdfException {
  XrefException(String message, {Object? cause}) : super(message, cause: cause);
}
