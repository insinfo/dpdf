import 'byte_array.dart';

/// Pairs a data block with its Reed-Solomon parity bytes.
class CraftBlockPair {
  final CraftByteArray _dataBytes;
  final CraftByteArray _errorCorrectionBytes;

  CraftBlockPair(this._dataBytes, this._errorCorrectionBytes);

  /// Returns data block of the pair
  CraftByteArray getDataBytes() {
    return _dataBytes;
  }

  /// Returns error correction block of the pair
  CraftByteArray getErrorCorrectionBytes() {
    return _errorCorrectionBytes;
  }
}
