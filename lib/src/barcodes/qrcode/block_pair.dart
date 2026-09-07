import 'byte_array.dart';

/// Pairs a data block with its Reed-Solomon parity bytes.
class BlockPair {
  final ByteArray _dataBytes;
  final ByteArray _errorCorrectionBytes;

  BlockPair(this._dataBytes, this._errorCorrectionBytes);

  /// Returns data block of the pair
  ByteArray getDataBytes() {
    return _dataBytes;
  }

  /// Returns error correction block of the pair
  ByteArray getErrorCorrectionBytes() {
    return _errorCorrectionBytes;
  }
}
