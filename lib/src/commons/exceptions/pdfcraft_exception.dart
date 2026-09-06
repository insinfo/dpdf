/// An operation failure carrying a readable diagnosis and its optional cause.
class PdfcraftException implements Exception {
  final String message;
  final Object? cause;

  PdfcraftException(this.message, [this.cause]);

  PdfcraftException.withDefaultMessage()
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
class CraftAggregatedException extends PdfcraftException {
  final List<Exception> innerExceptions;

  CraftAggregatedException(super.message, this.innerExceptions, [super.cause]);

  factory CraftAggregatedException.fromExceptions(
          String message, List<Exception> exceptions) =>
      CraftAggregatedException(message, exceptions);

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
