/// Utilities class for CSS operations.
class CssUtils {
  CssUtils._();

  static const double EPSILON = 1e-6;

  /// Helper method for comparing floating point numbers
  static bool compareFloats(double d1, double d2) {
    return (d1 - d2).abs() < EPSILON;
  }

  /// Unquotes the passed string, e.g. parse "text" to text.
  static String extractUnquotedString(String str) {
    if ((str.startsWith("'") && str.endsWith("'")) ||
        (str.startsWith("\"") && str.endsWith("\""))) {
      if (str.length >= 2) {
        return str.substring(1, str.length - 1).trim();
      }
      return "";
    } else {
      return str;
    }
  }

  /// Extracts url("file.jpg") to file.jpg.
  static String extractUrl(String url) {
    String trimmedUrl = url.trim();
    if (trimmedUrl.startsWith("url(")) {
      String urlString = trimmedUrl.substring(4).trim();
      if (!urlString.endsWith(")")) {
        return url;
      }
      urlString = urlString.substring(0, urlString.length - 1).trim();
      return extractUnquotedString(urlString);
    } else {
      // assume it's an url without wrapping in "url()"
      return extractUnquotedString(url);
    }
  }
}
