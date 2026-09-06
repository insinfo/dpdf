import 'logger.dart';

/// Resolves log sinks by component name. Factories are invoked for each lookup.
class LogManager {
  static Logger _console(String name) => ConsoleLogger(name);
  static Logger Function(String) _create = _console;

  /// Changes the resolver used by subsequent lookups.
  static void setLoggerFactory(Logger Function(String) factory) {
    _create = factory;
  }

  /// Restores console output after an application or test installed a resolver.
  static void resetLoggerFactory() {
    _create = _console;
  }

  static Logger getLogger(Type type) => getLoggerByName(type.toString());

  static Logger getLoggerByName(String name) => _create(name);
}
