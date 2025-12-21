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
import 'io_exception_message_constant.dart';

/// Exception class for exceptions in io module.
class IoException extends ITextException {
  /// Object for more details.
  Object? obj;

  /// Message parameters for formatting.
  List<Object>? _messageParams;

  /// Creates a new IoException.
  ///
  /// [message] the detail message.
  IoException(super.message, [super.cause]);

  /// Creates a new IoException from a cause.
  ///
  /// [cause] the cause of the exception.
  IoException.fromCause(Object cause)
      : super(IoExceptionMessageConstant.unknownIoException, cause);

  /// Creates a new IoException with an object for details.
  ///
  /// [message] the detail message.
  /// [obj] an object for more details.
  IoException.withObject(String message, this.obj) : super(message);

  /// Creates a new IoException with message, cause and object.
  ///
  /// [message] the detail message.
  /// [cause] the cause of the exception.
  /// [obj] an object for more details.
  IoException.full(String message, Object? cause, this.obj)
      : super(message, cause);

  @override
  String get message {
    if (_messageParams == null || _messageParams!.isEmpty) {
      return super.message;
    } else {
      return _formatMessage(super.message, _messageParams!);
    }
  }

  /// Gets additional params for Exception message.
  List<Object> getMessageParams() {
    return _messageParams ?? [];
  }

  /// Sets additional params for Exception message.
  ///
  /// [messageParams] additional params.
  /// Returns object itself for chaining.
  IoException setMessageParams(List<Object> messageParams) {
    _messageParams = List.from(messageParams);
    return this;
  }

  /// Formats a message with parameters, replacing {0}, {1}, etc.
  String _formatMessage(String template, List<Object> params) {
    var result = template;
    for (var i = 0; i < params.length; i++) {
      result = result.replaceAll('{$i}', params[i].toString());
    }
    return result;
  }

  @override
  String toString() {
    if (cause != null) {
      return 'IoException: $message\nCaused by: $cause';
    }
    return 'IoException: $message';
  }
}
