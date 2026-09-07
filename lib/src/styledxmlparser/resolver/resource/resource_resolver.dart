class ResourceResolver {
  ResourceResolver(String? baseUri, [dynamic resourceResolver]);

  String? getBaseUri() => null;

  static bool isDataSrc(String src) => src.startsWith("data:");

  dynamic resolveAgainstBaseUri(String uri) {
    // Return a wrapper that has toExternalForm()
    return _UriWrapper(uri);
  }

  Stream<List<int>>? retrieveResourceAsInputStream(String uri) => null;
}

class _UriWrapper {
  final String uri;
  _UriWrapper(this.uri);
  String toExternalForm() => uri;
}
