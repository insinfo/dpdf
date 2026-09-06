/// This enum encapsulates the four error correction levels defined by the QR code standard.
class CraftErrorCorrectionLevel {
  /// L = ~7% correction
  static final CraftErrorCorrectionLevel L =
      CraftErrorCorrectionLevel._(0, 0x01, "L");

  /// M = ~15% correction
  static final CraftErrorCorrectionLevel M =
      CraftErrorCorrectionLevel._(1, 0x00, "M");

  /// Q = ~25% correction
  static final CraftErrorCorrectionLevel Q =
      CraftErrorCorrectionLevel._(2, 0x03, "Q");

  /// H = ~30% correction
  static final CraftErrorCorrectionLevel H =
      CraftErrorCorrectionLevel._(3, 0x02, "H");

  static final List<CraftErrorCorrectionLevel> FOR_BITS = [M, L, H, Q];

  final int _ordinal;
  final int _bits;
  final String _name;

  CraftErrorCorrectionLevel._(this._ordinal, this._bits, this._name);

  int get ordinal => _ordinal;

  int get bits => _bits;

  String get name => _name;

  @override
  String toString() {
    return _name;
  }

  /// [bits] int containing the two bits encoding a QR Code's error correction level
  /// Returns [ErrorCorrectionLevel] representing the encoded error correction level
  static CraftErrorCorrectionLevel forBits(int bits) {
    if (bits < 0 || bits >= FOR_BITS.length) {
      throw ArgumentError();
    }
    return FOR_BITS[bits];
  }
}
