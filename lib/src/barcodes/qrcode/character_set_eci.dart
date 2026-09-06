/// Encapsulates a Character Set ECI, according to "Extended Channel Interpretations" 5.3.1.1
/// of ISO 18004.
class CharacterSetECI {
  static Map<String, CharacterSetECI>? _NAME_TO_ECI;

  static void _initialize() {
    Map<String, CharacterSetECI> n = {};
    _addCharacterSet(0, "Cp437", n);
    _addCharacterSetList(1, ["ISO8859_1", "ISO-8859-1"], n);
    _addCharacterSet(2, "Cp437", n);
    _addCharacterSetList(3, ["ISO8859_1", "ISO-8859-1"], n);
    _addCharacterSetList(4, ["ISO8859_2", "ISO-8859-2"], n);
    _addCharacterSetList(5, ["ISO8859_3", "ISO-8859-3"], n);
    _addCharacterSetList(6, ["ISO8859_4", "ISO-8859-4"], n);
    _addCharacterSetList(7, ["ISO8859_5", "ISO-8859-5"], n);
    _addCharacterSetList(8, ["ISO8859_6", "ISO-8859-6"], n);
    _addCharacterSetList(9, ["ISO8859_7", "ISO-8859-7"], n);
    _addCharacterSetList(10, ["ISO8859_8", "ISO-8859-8"], n);
    _addCharacterSetList(11, ["ISO8859_9", "ISO-8859-9"], n);
    _addCharacterSetList(12, ["ISO8859_10", "ISO-8859-10"], n);
    _addCharacterSetList(13, ["ISO8859_11", "ISO-8859-11"], n);
    _addCharacterSetList(15, ["ISO8859_13", "ISO-8859-13"], n);
    _addCharacterSetList(16, ["ISO8859_14", "ISO-8859-14"], n);
    _addCharacterSetList(17, ["ISO8859_15", "ISO-8859-15"], n);
    _addCharacterSetList(18, ["ISO8859_16", "ISO-8859-16"], n);
    _addCharacterSetList(20, ["SJIS", "Shift_JIS"], n);
    _NAME_TO_ECI = n;
  }

  final String _encodingName;
  final int _value;

  CharacterSetECI._(this._value, this._encodingName);

  String getEncodingName() {
    return _encodingName;
  }

  int getValue() {
    return _value;
  }

  static void _addCharacterSet(
      int value, String encodingName, Map<String, CharacterSetECI> n) {
    CharacterSetECI eci = CharacterSetECI._(value, encodingName);
    n[encodingName] = eci;
  }

  static void _addCharacterSetList(
      int value, List<String> encodingNames, Map<String, CharacterSetECI> n) {
    CharacterSetECI eci = CharacterSetECI._(value, encodingNames[0]);
    for (int i = 0; i < encodingNames.length; i++) {
      n[encodingNames[i]] = eci;
    }
  }

  static CharacterSetECI? getCharacterSetECIByName(String name) {
    if (_NAME_TO_ECI == null) {
      _initialize();
    }
    return _NAME_TO_ECI![name];
  }
}
