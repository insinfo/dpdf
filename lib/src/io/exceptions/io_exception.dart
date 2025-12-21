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
