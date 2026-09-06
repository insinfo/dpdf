/// Base exception class for  library.
///
/// This is the superclass for all exceptions thrown by .
class PdfcraftException implements Exception {
  /// The error message.
  final String message;

  /// The underlying cause of this exception, if any.
  final Object? cause;

  /// Creates a new Exception with the given message.
  Exception(this.message, [this.cause]);

  /// Creates a new Exception with default message.
  PdfcraftException.withDefaultMessage()
      : message = 'Unknown  exception',
        cause = null;

  @override
  String toString() {
    if (cause != null) {
      return 'Exception: $message\nCaused by: $cause';
    }
    return 'Exception: $message';
  }

  /// Returns the message of the exception.
  String getMessage() => message;

  /// Returns the cause of the exception.
  Object? getCause() => cause;
}

/// Exception for aggregate errors containing multiple exceptions.
class AggregatedException extends PdfcraftException {
  /// List of inner exceptions.
  final List<Exception> innerExceptions;

  /// Creates a new AggregatedException.
  AggregatedException(super.message, this.innerExceptions, [super.cause]);

  /// Creates from a list of exceptions.
  factory AggregatedException.fromExceptions(
    String message,
    List<Exception> exceptions,
  ) {
    return AggregatedException(message, exceptions);
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('AggregatedException: $message');
    for (var i = 0; i < innerExceptions.length; i++) {
      buffer.writeln('  [$i] ${innerExceptions[i]}');
    }
    return buffer.toString();
  }
}
