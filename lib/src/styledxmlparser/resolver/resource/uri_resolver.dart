/// Utilities class to resolve URIs.
class UriResolver {
  final Uri baseUrl;
  final bool isLocalBaseUri;

  UriResolver(String? baseUri)
      : baseUrl = _resolveBaseUri(baseUri),
        isLocalBaseUri = _isLocal(baseUri);

  String getBaseUri() => baseUrl.toString();

  Uri resolveAgainstBaseUri(String uriString) {
    return baseUrl.resolve(uriString);
  }

  static Uri _resolveBaseUri(String? baseUri) {
    if (baseUri == null || baseUri.isEmpty) {
      return Uri.file(""); // Current directory
    }
    try {
      if (baseUri.startsWith("http://") ||
          baseUri.startsWith("https://") ||
          baseUri.startsWith("file://")) {
        var uri = Uri.parse(baseUri);
        if (!uri.path.endsWith("/") && !uri.path.contains(".")) {
          uri = uri.replace(path: "${uri.path}/");
        }
        return uri;
      }
      return Uri.file(baseUri);
    } catch (_) {
      return Uri.file("");
    }
  }

  static bool _isLocal(String? baseUri) {
    if (baseUri == null || baseUri.isEmpty) return true;
    return baseUri.startsWith("file://") || !baseUri.contains("://");
  }
}
