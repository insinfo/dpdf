/// An operation failure carrying a readable diagnosis and its optional cause.
class DpdfException implements Exception {
  final String message;
  final Object? cause;

  DpdfException(this.message, [this.cause]);

  DpdfException.withDefaultMessage()
      : this('PDF processing failed without a diagnostic message.');

  String getMessage() => message;
  Object? getCause() => cause;

  @override
  String toString() {
    final description = 'Exception: $message';
    return cause == null ? description : '$description\nCaused by: $cause';
  }
}

/// Several failures reported together while retaining each individual error.
class AggregatedException extends DpdfException {
  final List<Exception> innerExceptions;

  AggregatedException(super.message, this.innerExceptions, [super.cause]);

  factory AggregatedException.fromExceptions(
          String message, List<Exception> exceptions) =>
      AggregatedException(message, exceptions);

  @override
  String toString() {
    final lines = <String>[
      'AggregatedException: $message',
      for (var index = 0; index < innerExceptions.length; index++)
        '  [$index] ${innerExceptions[index]}',
      if (cause != null) 'Caused by: $cause',
    ];
    return '${lines.join('\n')}\n';
  }
}
