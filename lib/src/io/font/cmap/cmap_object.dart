class CMapObject {
  static const int string = 1;
  static const int hexString = 2;
  static const int name = 3;
  static const int number = 4;
  static const int literal = 5;
  static const int array = 6;
  static const int dictionary = 7;
  static const int token = 8;

  final int type;
  Object? value;

  CMapObject(this.type, this.value);

  Object? getValue() => value;

  int getObjectType() => type;

  void setValue(Object? value) {
    this.value = value;
  }

  bool isString() => type == string || type == hexString;

  bool isHexString() => type == hexString;

  bool isName() => type == name;

  bool isNumber() => type == number;

  bool isLiteral() => type == literal;

  bool isArray() => type == array;

  bool isDictionary() => type == dictionary;

  bool isToken() => type == token;

  @override
  String toString() {
    if (type == string || type == hexString) {
      if (value is List<int>) {
        final content = value as List<int>;
        return String.fromCharCodes(content);
      }
    }
    return value.toString();
  }

  List<int>? toHexByteArray() {
    if (type == hexString) {
      return value as List<int>?;
    }
    return null;
  }
}
