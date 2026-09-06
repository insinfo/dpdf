abstract class ILogger {
  void logError(String message, [Object? error, StackTrace? stackTrace]);
  void logWarning(String message);
  void logInfo(String message);
  void logDebug(String message);
  void logTrace(String message);
}

class ConsoleLogger implements ILogger {
  final String name;
  ConsoleLogger(this.name);

  @override
  void logError(String message, [Object? error, StackTrace? stackTrace]) {
    print('[ERROR] $name: $message${error != null ? ' - $error' : ''}');
    if (stackTrace != null) print(stackTrace);
  }

  @override
  void logWarning(String message) {
    print('[WARN] $name: $message');
  }

  @override
  void logInfo(String message) {
    print('[INFO] $name: $message');
  }

  @override
  void logDebug(String message) {
    print('[DEBUG] $name: $message');
  }

  @override
  void logTrace(String message) {
    print('[TRACE] $name: $message');
  }
}
