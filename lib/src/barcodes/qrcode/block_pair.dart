import 'byte_array.dart';

/// Helper class that groups a block of databytes with its corresponding block of error correction block
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
