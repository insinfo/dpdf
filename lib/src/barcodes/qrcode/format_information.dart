import 'error_correction_level.dart';

/// Decoded correction level and mask from the duplicated QR format field.
class CraftFormatInformation {
  final CraftErrorCorrectionLevel _errorCorrectionLevel;
  final int _dataMask;
  CraftFormatInformation._(this._errorCorrectionLevel, this._dataMask);

  static int numBitsDiffering(int a, int b) {
    var remaining = (a ^ b).toUnsigned(32);
    var count = 0;
    while (remaining != 0) {
      remaining &= remaining - 1;
      count++;
    }
    return count;
  }

  static int _protectedWord(int payload) {
    var remainder = payload << 10;
    for (var degree = 14; degree >= 10; degree--) {
      if ((remainder & (1 << degree)) != 0) remainder ^= 0x537 << (degree - 10);
    }
    return ((payload << 10) | remainder) ^ 0x5412;
  }

  static CraftFormatInformation? decodeFormatInformation(
      int maskedFormatInfo1, int maskedFormatInfo2) {
    // Prefer ordinary format masking; retain recovery of unmasked legacy fields.
    for (final adjustment in [0, 0x5412]) {
      final candidates = <(int, int)>[];
      for (var value = 0; value < 32; value++) {
        final target = _protectedWord(value);
        final distances = [maskedFormatInfo1, maskedFormatInfo2]
            .map((observed) => numBitsDiffering(observed ^ adjustment, target));
        final distance = distances.reduce((a, b) => a < b ? a : b);
        if (distance <= 3) candidates.add((distance, value));
      }
      if (candidates.isEmpty) continue;
      candidates.sort(
          (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
      final payload = candidates.first.$2;
      return CraftFormatInformation._(
          CraftErrorCorrectionLevel.forBits(payload ~/ 8), payload % 8);
    }
    return null;
  }

  CraftErrorCorrectionLevel getErrorCorrectionLevel() => _errorCorrectionLevel;
  int getDataMask() => _dataMask;
  @override
  int get hashCode => _errorCorrectionLevel.ordinal * 8 + _dataMask;
  @override
  bool operator ==(Object other) =>
      other is CraftFormatInformation &&
      other._errorCorrectionLevel == _errorCorrectionLevel &&
      other._dataMask == _dataMask;
}
