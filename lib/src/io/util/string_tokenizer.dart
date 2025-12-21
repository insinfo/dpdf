class StringTokenizer {
  final String _str;
  final String _delimiters;
  int _position = 0;

  StringTokenizer(this._str, [this._delimiters = " \t\n\r\f"]);

  bool hasMoreTokens() {
    _skipDelimiters();
    return _position < _str.length;
  }

  String nextToken([String? delimiters]) {
    String delims = delimiters ?? _delimiters;
    _skipDelimiters(delims);

    if (_position >= _str.length) {
      throw Exception("No more tokens"); // NoSuchElementException
    }

    int start = _position;
    while (_position < _str.length && !delims.contains(_str[_position])) {
      _position++;
    }
    return _str.substring(start, _position);
  }

  void _skipDelimiters([String? delimiters]) {
    String delims = delimiters ?? _delimiters;
    while (_position < _str.length && delims.contains(_str[_position])) {
      _position++;
    }
  }
}
