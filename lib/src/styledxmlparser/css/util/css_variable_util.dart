class CssVariableUtil {
  static bool isCssVariable(String propertyName) {
    return propertyName.startsWith("--");
  }

  static void resolveCssVariables(Map<String, String> styles) {
    final resolved = <String, String?>{};
    final resolving = <String>{};
    late String? Function(String value) resolveValue;

    String? resolveVariable(String name) {
      if (resolved.containsKey(name)) return resolved[name];
      final source = styles[name];
      if (source == null || !resolving.add(name)) return null;
      final value = resolveValue(source);
      resolving.remove(name);
      resolved[name] = value;
      return value;
    }

    resolveValue = (String value) {
      final out = StringBuffer();
      var cursor = 0;
      while (cursor < value.length) {
        final start = value.indexOf('var(', cursor);
        if (start < 0) {
          out.write(value.substring(cursor));
          break;
        }
        out.write(value.substring(cursor, start));
        var depth = 1;
        var end = start + 4;
        while (end < value.length && depth > 0) {
          final code = value.codeUnitAt(end);
          if (code == 0x28) depth++;
          if (code == 0x29) depth--;
          end++;
        }
        if (depth != 0) return null;
        final arguments = value.substring(start + 4, end - 1);
        final comma = _firstTopLevelComma(arguments);
        final name =
            (comma < 0 ? arguments : arguments.substring(0, comma)).trim();
        if (!isCssVariable(name)) return null;
        String? replacement = resolveVariable(name);
        if (replacement == null && comma >= 0) {
          replacement = resolveValue(arguments.substring(comma + 1).trim());
        }
        if (replacement == null) return null;
        out.write(replacement);
        cursor = end;
      }
      return out.toString();
    };

    final entries = List<MapEntry<String, String>>.from(styles.entries);
    for (final entry in entries) {
      final value = resolveValue(entry.value);
      if (value == null) {
        styles.remove(entry.key);
      } else {
        styles[entry.key] = value;
      }
    }
  }

  static int _firstTopLevelComma(String value) {
    var depth = 0;
    for (var index = 0; index < value.length; index++) {
      final code = value.codeUnitAt(index);
      if (code == 0x28) depth++;
      if (code == 0x29 && depth > 0) depth--;
      if (code == 0x2c && depth == 0) return index;
    }
    return -1;
  }
}
