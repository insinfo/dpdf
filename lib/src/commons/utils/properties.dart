import 'dart:collection';
import 'dart:convert';

/// Basic implementation of Java-style properties file parser.
class Properties extends IterableBase<MapEntry<String, String>> {
  final Map<String, String> _map = {};

  Properties();

  /// Loads properties from a string.
  void loadFromString(String content) {
    final lines = LineSplitter.split(content);
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
        continue;
      }

      int eqIdx = line.indexOf('=');
      int colIdx = line.indexOf(':');
      int splitIdx = -1;

      if (eqIdx != -1 && colIdx != -1) {
        splitIdx = eqIdx < colIdx ? eqIdx : colIdx;
      } else {
        splitIdx = eqIdx != -1 ? eqIdx : colIdx;
      }

      if (splitIdx != -1) {
        final key = line.substring(0, splitIdx).trim();
        final value = line.substring(splitIdx + 1).trim();
        _map[key] = _unescape(value);
      } else {
        _map[line] = "";
      }
    }
  }

  /// Loads properties from a byte list.
  void loadFromBytes(List<int> bytes) {
    loadFromString(utf8.decode(bytes));
  }

  String _unescape(String value) {
    // Basic unescaping for common cases
    return value
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\\', r'\');
  }

  String? getProperty(String key) => _map[key];

  void setProperty(String key, String value) {
    _map[key] = value;
  }

  bool containsKey(String key) => _map.containsKey(key);

  String? operator [](String key) => _map[key];

  @override
  Iterator<MapEntry<String, String>> get iterator => _map.entries.iterator;

  int get length => _map.length;
}
