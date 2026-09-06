import 'byte_matrix.dart';
import 'error_correction_level.dart';
import 'mode.dart';

/// A QR code (short for "quick-response code") is a type of two-dimensional matrix barcode.
class QRCode {
  static const int NUM_MASK_PATTERNS = 8;

  Mode? _mode;
  ErrorCorrectionLevel? _ecLevel;
  int _version = -1;
  int _matrixWidth = -1;
  int _maskPattern = -1;
  int _numTotalBytes = -1;
  int _numDataBytes = -1;
  int _numECBytes = -1;
  int _numRSBlocks = -1;
  ByteMatrix? _matrix;

  QRCode();

  Mode? getMode() {
    return _mode;
  }

  ErrorCorrectionLevel? getECLevel() {
    return _ecLevel;
  }

  int getVersion() {
    return _version;
  }

  int getMatrixWidth() {
    return _matrixWidth;
  }

  int getMaskPattern() {
    return _maskPattern;
  }

  int getNumTotalBytes() {
    return _numTotalBytes;
  }

  int getNumDataBytes() {
    return _numDataBytes;
  }

  int getNumECBytes() {
    return _numECBytes;
  }

  int getNumRSBlocks() {
    return _numRSBlocks;
  }

  ByteMatrix? getMatrix() {
    return _matrix;
  }

  int at(int x, int y) {
    // The value must be zero or one.
    int value = _matrix!.get(x, y);
    if (!(value == 0 || value == 1)) {
      throw Exception("Bad value");
    }
    return value;
  }

  bool isValid() {
    return _mode != null &&
        _ecLevel != null &&
        _version != -1 &&
        _matrixWidth != -1 &&
        _maskPattern != -1 &&
        _numTotalBytes != -1 &&
        _numDataBytes != -1 &&
        _numECBytes != -1 &&
        _numRSBlocks != -1 &&
        isValidMaskPattern(_maskPattern) &&
        _numTotalBytes == _numDataBytes + _numECBytes &&
        _matrix != null &&
        _matrixWidth == _matrix!.getWidth() &&
        _matrix!.getWidth() == _matrix!.getHeight();
  }

  @override
  String toString() {
    StringBuffer result = StringBuffer();
    result.write("<<\n");
    result.write(" mode: ");
    result.write(_mode);
    result.write("\n ecLevel: ");
    result.write(_ecLevel);
    result.write("\n version: ");
    result.write(_version);
    result.write("\n matrixWidth: ");
    result.write(_matrixWidth);
    result.write("\n maskPattern: ");
    result.write(_maskPattern);
    result.write("\n numTotalBytes: ");
    result.write(_numTotalBytes);
    result.write("\n numDataBytes: ");
    result.write(_numDataBytes);
    result.write("\n numECBytes: ");
    result.write(_numECBytes);
    result.write("\n numRSBlocks: ");
    result.write(_numRSBlocks);
    if (_matrix == null) {
      result.write("\n matrix: null\n");
    } else {
      result.write("\n matrix:\n");
      result.write(_matrix.toString());
    }
    result.write(">>\n");
    return result.toString();
  }

  void setMode(Mode value) {
    _mode = value;
  }

  void setECLevel(ErrorCorrectionLevel value) {
    _ecLevel = value;
  }

  void setVersion(int value) {
    _version = value;
  }

  void setMatrixWidth(int value) {
    _matrixWidth = value;
  }

  void setMaskPattern(int value) {
    _maskPattern = value;
  }

  void setNumTotalBytes(int value) {
    _numTotalBytes = value;
  }

  void setNumDataBytes(int value) {
    _numDataBytes = value;
  }

  void setNumECBytes(int value) {
    _numECBytes = value;
  }

  void setNumRSBlocks(int value) {
    _numRSBlocks = value;
  }

  void setMatrix(ByteMatrix value) {
    _matrix = value;
  }

  static bool isValidMaskPattern(int maskPattern) {
    return maskPattern >= 0 && maskPattern < NUM_MASK_PATTERNS;
  }
}
