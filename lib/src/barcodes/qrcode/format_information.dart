import 'error_correction_level.dart';

/// Encapsulates a QR Code's format information, including the data mask used and
/// error correction level.
class FormatInformation {
  static const int _FORMAT_INFO_MASK_QR = 0x5412;

  /// See ISO 18004:2006, Annex C, Table C.1
  static final List<List<int>> _FORMAT_INFO_DECODE_LOOKUP = [
    [0x5412, 0x00],
    [0x5125, 0x01],
    [0x5E7C, 0x02],
    [0x5B4B, 0x03],
    [0x45F9, 0x04],
    [0x40CE, 0x05],
    [0x4F97, 0x06],
    [0x4AA0, 0x07],
    [0x77C4, 0x08],
    [0x72F3, 0x09],
    [0x7DAA, 0x0A],
    [0x789D, 0x0B],
    [0x662F, 0x0C],
    [0x6318, 0x0D],
    [0x6C41, 0x0E],
    [0x6976, 0x0F],
    [0x1689, 0x10],
    [0x13BE, 0x11],
    [0x1CE7, 0x12],
    [0x19D0, 0x13],
    [0x0762, 0x14],
    [0x0255, 0x15],
    [0x0D0C, 0x16],
    [0x083B, 0x17],
    [0x355F, 0x18],
    [0x3068, 0x19],
    [0x3F31, 0x1A],
    [0x3A06, 0x1B],
    [0x24B4, 0x1C],
    [0x2183, 0x1D],
    [0x2EDA, 0x1E],
    [0x2BED, 0x1F]
  ];

  /// Offset i holds the number of 1 bits in the binary representation of i
  static final List<int> _BITS_SET_IN_HALF_BYTE = [
    0,
    1,
    1,
    2,
    1,
    2,
    2,
    3,
    1,
    2,
    2,
    3,
    2,
    3,
    3,
    4
  ];

  final ErrorCorrectionLevel _errorCorrectionLevel;
  final int _dataMask;

  FormatInformation._(this._errorCorrectionLevel, this._dataMask);

  static int numBitsDiffering(int a, int b) {
    // a now has a 1 bit exactly where its bit differs with b's
    a ^= b;
    // Count bits set quickly with a series of lookups:
    return _BITS_SET_IN_HALF_BYTE[a & 0x0F] +
        _BITS_SET_IN_HALF_BYTE[(a >> 4) & 0x0F] +
        _BITS_SET_IN_HALF_BYTE[(a >> 8) & 0x0F] +
        _BITS_SET_IN_HALF_BYTE[(a >> 12) & 0x0F] +
        _BITS_SET_IN_HALF_BYTE[(a >> 16) & 0x0F] +
        _BITS_SET_IN_HALF_BYTE[(a >> 20) & 0x0F] +
        _BITS_SET_IN_HALF_BYTE[(a >> 24) & 0x0F] +
        _BITS_SET_IN_HALF_BYTE[(a >> 28) & 0x0F];
  }

  static FormatInformation? decodeFormatInformation(
      int maskedFormatInfo1, int maskedFormatInfo2) {
    FormatInformation? formatInfo =
        _doDecodeFormatInformation(maskedFormatInfo1, maskedFormatInfo2);
    if (formatInfo != null) {
      return formatInfo;
    }
    // Should return null, but, some QR codes apparently
    // do not mask this info. Try again by actually masking the pattern
    // first
    return _doDecodeFormatInformation(maskedFormatInfo1 ^ _FORMAT_INFO_MASK_QR,
        maskedFormatInfo2 ^ _FORMAT_INFO_MASK_QR);
  }

  static FormatInformation? _doDecodeFormatInformation(
      int maskedFormatInfo1, int maskedFormatInfo2) {
    // Find the int in FORMAT_INFO_DECODE_LOOKUP with fewest bits differing
    int bestDifference = 0x7FFFFFFF;
    int bestFormatInfo = 0;
    for (int i = 0; i < _FORMAT_INFO_DECODE_LOOKUP.length; i++) {
      List<int> decodeInfo = _FORMAT_INFO_DECODE_LOOKUP[i];
      int targetInfo = decodeInfo[0];
      if (targetInfo == maskedFormatInfo1 || targetInfo == maskedFormatInfo2) {
        // Found an exact match
        return _fromBits(decodeInfo[1]);
      }
      int bitsDifference = numBitsDiffering(maskedFormatInfo1, targetInfo);
      if (bitsDifference < bestDifference) {
        bestFormatInfo = decodeInfo[1];
        bestDifference = bitsDifference;
      }
      if (maskedFormatInfo1 != maskedFormatInfo2) {
        // also try the other option
        bitsDifference = numBitsDiffering(maskedFormatInfo2, targetInfo);
        if (bitsDifference < bestDifference) {
          bestFormatInfo = decodeInfo[1];
          bestDifference = bitsDifference;
        }
      }
    }
    // Hamming distance of the 32 masked codes is 7, by construction, so <= 3 bits
    // differing means we found a match
    if (bestDifference <= 3) {
      return _fromBits(bestFormatInfo);
    }
    return null;
  }

  static FormatInformation _fromBits(int formatInfo) {
    // Bits 3,4
    ErrorCorrectionLevel errorCorrectionLevel =
        ErrorCorrectionLevel.forBits((formatInfo >> 3) & 0x03);
    // Bottom 3 bits
    int dataMask = formatInfo & 0x07;
    return FormatInformation._(errorCorrectionLevel, dataMask);
  }

  ErrorCorrectionLevel getErrorCorrectionLevel() {
    return _errorCorrectionLevel;
  }

  int getDataMask() {
    return _dataMask;
  }

  @override
  int get hashCode {
    return (_errorCorrectionLevel.ordinal << 3) | _dataMask;
  }

  @override
  bool operator ==(Object other) {
    if (other is! FormatInformation) {
      return false;
    }
    return _errorCorrectionLevel == other._errorCorrectionLevel &&
        _dataMask == other._dataMask;
  }
}
