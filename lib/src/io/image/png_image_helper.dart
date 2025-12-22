import 'dart:typed_data';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

class PngImageHelper {
  static const List<int> PNGID = [137, 80, 78, 71, 13, 10, 26, 10];

  static void processImage(ImageData image) {
    if (image.originalType != ImageType.PNG) {
      throw ArgumentError("PNG image expected");
    }

    Uint8List? data = image.getData();
    if (data == null) {
      throw IoException(IoExceptionMessageConstant.ioException);
    }

    image.imageSize = data.length;
    _processPng(data, image);
  }

  static void _processPng(Uint8List data, ImageData image) {
    int pos = 0;

    int read() {
      if (pos >= data.length) return -1;
      return data[pos++];
    }

    int getInt() {
      int b1 = read();
      int b2 = read();
      int b3 = read();
      int b4 = read();
      if (b1 == -1 || b2 == -1 || b3 == -1 || b4 == -1) return -1;
      return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
    }

    String getMarker() {
      List<int> bytes = [read(), read(), read(), read()];
      if (bytes.contains(-1)) return "";
      return String.fromCharCodes(bytes);
    }

    // Check PNG signature
    for (int i = 0; i < PNGID.length; i++) {
      if (read() != PNGID[i]) {
        throw IoException("Not a valid PNG file");
      }
    }

    bool ihdrFound = false;

    while (pos < data.length) {
      int len = getInt();
      String marker = getMarker();

      if (marker == "IHDR") {
        image.width = getInt().toDouble();
        image.height = getInt().toDouble();
        image.bpc = read();
        image.colorEncodingComponentsNumber = _getColorComponents(read());
        // Skip compression, filter, interlace
        pos += 3;
        ihdrFound = true;
      } else if (marker == "IEND") {
        break;
      } else {
        // Skip chunk data + CRC
        pos += len + 4;
      }

      if (ihdrFound && marker == "IHDR") {
        // Skip CRC for IHDR
        pos += 4;
      }
    }

    if (!ihdrFound) {
      throw IoException("IHDR chunk not found");
    }
  }

  static int _getColorComponents(int colorType) {
    switch (colorType) {
      case 0:
        return 1; // Greyscale
      case 2:
        return 3; // Truecolour
      case 3:
        return 1; // Indexed
      case 4:
        return 2; // Greyscale with alpha
      case 6:
        return 4; // Truecolour with alpha
      default:
        return 0;
    }
  }
}
