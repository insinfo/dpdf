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

/// Base exception class for iText library.
///
/// This is the superclass for all exceptions thrown by iText.
class ITextException implements Exception {
  /// The error message.
  final String message;

  /// The underlying cause of this exception, if any.
  final Object? cause;

  /// Creates a new ITextException with the given message.
  ITextException(this.message, [this.cause]);

  /// Creates a new ITextException with default message.
  ITextException.withDefaultMessage()
      : message = 'Unknown iText exception',
        cause = null;

  @override
  String toString() {
    if (cause != null) {
      return 'ITextException: $message\nCaused by: $cause';
    }
    return 'ITextException: $message';
  }

  /// Returns the message of the exception.
  String getMessage() => message;

  /// Returns the cause of the exception.
  Object? getCause() => cause;
}

/// Exception for aggregate errors containing multiple exceptions.
class AggregatedITextException extends ITextException {
  /// List of inner exceptions.
  final List<Exception> innerExceptions;

  /// Creates a new AggregatedITextException.
  AggregatedITextException(super.message, this.innerExceptions, [super.cause]);

  /// Creates from a list of exceptions.
  factory AggregatedITextException.fromExceptions(
    String message,
    List<Exception> exceptions,
  ) {
    return AggregatedITextException(message, exceptions);
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('AggregatedITextException: $message');
    for (var i = 0; i < innerExceptions.length; i++) {
      buffer.writeln('  [$i] ${innerExceptions[i]}');
    }
    return buffer.toString();
  }
}
