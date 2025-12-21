import 'dart:io';

class AdobeGlyphList {
  static final Map<int, String> _unicode2names = {};
  static final Map<String, int> _names2unicode = {};
  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    try {
      var file = File('lib/src/io/resources/AdobeGlyphList.txt');
      if (!file.existsSync()) {
        // Fallback for tests or if path differs
        file = File('src/io/resources/AdobeGlyphList.txt'); // relative path try
      }

      if (file.existsSync()) {
        var lines = file.readAsLinesSync();
        for (var line in lines) {
          if (line.startsWith('#')) continue;
          var parts = line.split(';');
          if (parts.length == 2) {
            String name = parts[0];
            String hex = parts[1];
            // AdobeGlyphList could contains symbols with marks, e.g.:
            // resh;05E8
            // reshhatafpatah;05E8 05B2
            // So in this case we will just skip this nam (as per C# code logic that checks for more tokens)
            // The logic in C# tokenizer was: name, hex, check if more tokens.
            // My split by ';' gives 2 parts. if hex contains space, it means multiple unicodes.
            // C# logic: String hex = t2.NextToken(); ... if (t2.HasMoreTokens()) continue;

            if (hex.trim().contains(' ')) {
              continue;
            }

            try {
              int num = int.parse(hex, radix: 16);
              _unicode2names[num] = name;
              _names2unicode[name] = num;
            } catch (e) {
              // ignore
            }
          }
        }
      } else {
        print("AdobeGlyphList.txt not found.");
      }
    } catch (e) {
      print("AdobeGlyphList loading error: $e");
    } finally {
      _initialized = true;
    }
  }

  static int nameToUnicode(String name) {
    _ensureInitialized();
    int? v = _names2unicode[name];
    if (v == null && name.length == 7 && name.toLowerCase().startsWith('uni')) {
      try {
        return int.parse(name.substring(3), radix: 16);
      } catch (_) {}
    }
    return v ?? -1;
  }

  static String? unicodeToName(int num) {
    _ensureInitialized();
    return _unicode2names[num];
  }
}
