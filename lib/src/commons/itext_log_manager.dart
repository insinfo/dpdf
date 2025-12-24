import 'i_logger.dart';

class ITextLogManager {
  static ILogger Function(String) _loggerFactory =
      (name) => ConsoleLogger(name);

  static void setLoggerFactory(ILogger Function(String) factory) {
    _loggerFactory = factory;
  }

  static ILogger getLogger(Type type) {
    return _loggerFactory(type.toString());
  }

  static ILogger getLoggerByName(String name) {
    return _loggerFactory(name);
  }
}
