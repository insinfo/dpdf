import 'version.dart';

/// See ISO 18004:2006, 6.4.1, Tables 2 and 3. This enum encapsulates the various modes in which
/// data can be encoded to bits in the QR code standard.
class CraftMode {
  // Not really a mode...
  static final CraftMode TERMINATOR =
      CraftMode._([0, 0, 0], 0x00, "TERMINATOR");

  static final CraftMode NUMERIC = CraftMode._([10, 12, 14], 0x01, "NUMERIC");

  static final CraftMode ALPHANUMERIC =
      CraftMode._([9, 11, 13], 0x02, "ALPHANUMERIC");

  // Not supported
  static final CraftMode STRUCTURED_APPEND =
      CraftMode._([0, 0, 0], 0x03, "STRUCTURED_APPEND");

  static final CraftMode BYTE = CraftMode._([8, 16, 16], 0x04, "BYTE");

  // character counts don't apply
  static final CraftMode ECI = CraftMode._(null, 0x07, "ECI");

  static final CraftMode KANJI = CraftMode._([8, 10, 12], 0x08, "KANJI");

  static final CraftMode FNC1_FIRST_POSITION =
      CraftMode._(null, 0x05, "FNC1_FIRST_POSITION");

  static final CraftMode FNC1_SECOND_POSITION =
      CraftMode._(null, 0x09, "FNC1_SECOND_POSITION");

  final List<int>? _characterCountBitsForVersions;
  final int _bits;
  final String _name;

  CraftMode._(this._characterCountBitsForVersions, this._bits, this._name);

  static CraftMode forBits(int bits) {
    switch (bits) {
      case 0x0:
        return TERMINATOR;
      case 0x1:
        return NUMERIC;
      case 0x2:
        return ALPHANUMERIC;
      case 0x3:
        return STRUCTURED_APPEND;
      case 0x4:
        return BYTE;
      case 0x5:
        return FNC1_FIRST_POSITION;
      case 0x7:
        return ECI;
      case 0x8:
        return KANJI;
      case 0x9:
        return FNC1_SECOND_POSITION;
      default:
        throw ArgumentError();
    }
  }

  /// [version] - version in question
  /// Returns number of bits used, in this QR Code symbol, to encode the count of characters
  int getCharacterCountBits(CraftVersion version) {
    if (_characterCountBitsForVersions == null) {
      throw ArgumentError("Character count doesn't apply to this mode");
    }
    int number = version.getVersionNumber();
    int offset;
    if (number <= 9) {
      offset = 0;
    } else if (number <= 26) {
      offset = 1;
    } else {
      offset = 2;
    }
    return _characterCountBitsForVersions[offset];
  }

  int getBits() {
    return _bits;
  }

  String getName() {
    return _name;
  }

  @override
  String toString() {
    return _name;
  }
}
