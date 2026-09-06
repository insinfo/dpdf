import 'dart:math';
import 'dart:typed_data';

import 'byte_matrix.dart';
import 'encode_hint_type.dart';
import 'encoder.dart';
import 'error_correction_level.dart';
import 'qr_code.dart';

/// This object renders a QR Code as a ByteMatrix 2D array of greyscale values.
class QRCodeWriter {
  static const int _QUIET_ZONE_SIZE = 4;

  /// Encode a string into a QR code with dimensions width x height.
  /// [contents] - String to encode into the QR code
  /// [width] - width of the QR-code
  /// [height] - height of the QR-code
  /// [hints] - Map containing suggestions for error-correction level and version
  /// Returns 2D Greyscale map containing the visual representation of the QR-code, stored as a Bytematrix
  ByteMatrix encode(String contents, int width, int height,
      [Map<EncodeHintType, dynamic>? hints]) {
    if (contents.isEmpty) {
      throw ArgumentError("Found empty contents");
    }
    if (width < 0 || height < 0) {
      throw ArgumentError(
          "Requested dimensions are too small: ${width}x$height");
    }
    ErrorCorrectionLevel errorCorrectionLevel = ErrorCorrectionLevel.L;
    if (hints != null && hints.containsKey(EncodeHintType.ERROR_CORRECTION)) {
      ErrorCorrectionLevel? requestedECLevel =
          hints[EncodeHintType.ERROR_CORRECTION] as ErrorCorrectionLevel?;
      if (requestedECLevel != null) {
        errorCorrectionLevel = requestedECLevel;
      }
    }
    QRCode code = QRCode();
    Encoder.encode(contents, errorCorrectionLevel, hints, code);
    return _renderResult(code, width, height);
  }

  // Note that the input matrix uses 0 == white, 1 == black, while the output matrix uses
  // 0 == black, 255 == white (i.e. an 8 bit greyscale bitmap).
  static ByteMatrix _renderResult(QRCode code, int width, int height) {
    ByteMatrix input = code.getMatrix()!;
    int inputWidth = input.getWidth();
    int inputHeight = input.getHeight();
    int qrWidth = inputWidth + (_QUIET_ZONE_SIZE << 1);
    int qrHeight = inputHeight + (_QUIET_ZONE_SIZE << 1);
    int outputWidth = max(width, qrWidth);
    int outputHeight = max(height, qrHeight);
    int multiple = min(outputWidth ~/ qrWidth, outputHeight ~/ qrHeight);
    // Padding includes both the quiet zone and the extra white pixels to accommodate the requested
    // dimensions. For example, if input is 25x25 the QR will be 33x33 including the quiet zone.
    // If the requested size is 200x160, the multiple will be 4, for a QR of 132x132. These will
    // handle all the padding from 100x100 (the actual QR) up to 200x160.
    int leftPadding = (outputWidth - (inputWidth * multiple)) ~/ 2;
    int topPadding = (outputHeight - (inputHeight * multiple)) ~/ 2;
    ByteMatrix output = ByteMatrix(outputWidth, outputHeight);
    List<Uint8List> outputArray = output.getArray();
    // We could be tricky and use the first row in each set of multiple as the temporary storage,
    // instead of allocating this separate array.
    Uint8List row = Uint8List(outputWidth);
    // 1. Write the white lines at the top
    for (int y = 0; y < topPadding; y++) {
      _setRowColor(outputArray[y], 255);
    }
    // 2. Expand the QR image to the multiple
    List<Uint8List> inputArray = input.getArray();
    for (int y = 0; y < inputHeight; y++) {
      // a. Write the white pixels at the left of each row
      for (int x = 0; x < leftPadding; x++) {
        row[x] = 255;
      }
      // b. Write the contents of this row of the barcode
      int offset = leftPadding;
      for (int x = 0; x < inputWidth; x++) {
        int value = (inputArray[y][x] == 1) ? 0 : 255;
        for (int z = 0; z < multiple; z++) {
          row[offset + z] = value;
        }
        offset += multiple;
      }
      // c. Write the white pixels at the right of each row
      offset = leftPadding + (inputWidth * multiple);
      for (int x = offset; x < outputWidth; x++) {
        row[x] = 255;
      }
      // d. Write the completed row multiple times
      offset = topPadding + (y * multiple);
      for (int z = 0; z < multiple; z++) {
        List.copyRange(outputArray[offset + z], 0, row, 0, outputWidth);
      }
    }
    // 3. Write the white lines at the bottom
    int offset1 = topPadding + (inputHeight * multiple);
    for (int y = offset1; y < outputHeight; y++) {
      _setRowColor(outputArray[y], 255);
    }
    return output;
  }

  static void _setRowColor(Uint8List row, int value) {
    for (int x = 0; x < row.length; x++) {
      row[x] = value;
    }
  }
}
