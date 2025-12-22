import 'dart:typed_data';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

class JpegImageHelper {
  static const int NOT_A_MARKER = -1;
  static const int VALID_MARKER = 0;
  static const List<int> VALID_MARKERS = [0xC0, 0xC1, 0xC2];
  static const int UNSUPPORTED_MARKER = 1;
  static const List<int> UNSUPPORTED_MARKERS = [
    0xC3,
    0xC5,
    0xC6,
    0xC7,
    0xC8,
    0xC9,
    0xCA,
    0xCB,
    0xCD,
    0xCE,
    0xCF
  ];
  static const int NOPARAM_MARKER = 2;
  static const List<int> NOPARAM_MARKERS = [
    0xD0,
    0xD1,
    0xD2,
    0xD3,
    0xD4,
    0xD5,
    0xD6,
    0xD7,
    0xD8,
    0x01
  ];

  static const int M_APP0 = 0xE0;
  static const int M_APP2 = 0xE2;
  static const int M_APPE = 0xEE;
  static const int M_APPD = 0xED;

  static const List<int> JFIF_ID = [0x4A, 0x46, 0x49, 0x46, 0x00];

  static void processImage(ImageData image) {
    if (image.originalType != ImageType.JPEG) {
      throw ArgumentError("JPEG image expected");
    }

    Uint8List? data = image.getData();
    if (data == null) {
      throw IoException(IoExceptionMessageConstant.ioException);
    }

    image.imageSize = data.length;
    _processParameters(data, image);
    _updateAttributes(image);
  }

  static void _updateAttributes(ImageData image) {
    image.filter = "DCTDecode";
    if (image.colorTransform == 0) {
      image.decodeParms = {"ColorTransform": 0};
    }
    int colorComponents = image.colorEncodingComponentsNumber;
    if (colorComponents != 1 && colorComponents != 3 && image.inverted) {
      image.decode = [1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0];
    }
  }

  static void _processParameters(Uint8List data, ImageData image) {
    int pos = 0;

    int read() {
      if (pos >= data.length) return -1;
      return data[pos++];
    }

    int getShort() {
      int b1 = read();
      int b2 = read();
      if (b1 == -1 || b2 == -1) return -1;
      return (b1 << 8) | b2;
    }

    void skip(int n) {
      pos += n;
    }

    if (read() != 0xFF || read() != 0xD8) {
      throw IoException(IoExceptionMessageConstant.isNotAValidJpegFile);
    }

    bool firstPass = true;
    while (true) {
      int v = read();
      if (v < 0)
        throw IoException(
            IoExceptionMessageConstant.prematureEofWhileReadingJpeg);

      if (v == 0xFF) {
        int marker = read();
        if (marker == -1)
          throw IoException(
              IoExceptionMessageConstant.prematureEofWhileReadingJpeg);

        if (firstPass && marker == M_APP0) {
          firstPass = false;
          int len = getShort();
          if (len < 16) {
            skip(len - 2);
            continue;
          }

          bool found = true;
          for (int k = 0; k < JFIF_ID.length; k++) {
            if (data[pos + k] != JFIF_ID[k]) {
              found = false;
              break;
            }
          }

          if (!found) {
            skip(len - 2);
            continue;
          }

          skip(JFIF_ID.length);
          skip(2); // version
          int units = read();
          int dx = getShort();
          int dy = getShort();

          if (units == 1) {
            image.dpiX = dx;
            image.dpiY = dy;
          } else if (units == 2) {
            image.dpiX = (dx * 2.54 + 0.5).toInt();
            image.dpiY = (dy * 2.54 + 0.5).toInt();
          }

          skip(len - 2 - JFIF_ID.length - 7);
          continue;
        }

        if (marker == M_APPE) {
          int len = getShort() - 2;
          if (len >= 5) {
            String s = String.fromCharCodes(data.sublist(pos, pos + 5));
            if (s == "Adobe") {
              image.inverted = true;
            }
          }
          skip(len);
          continue;
        }

        firstPass = false;
        int markertype = _getMarkerType(marker);
        if (markertype == VALID_MARKER) {
          skip(2); // length
          if (read() != 0x08) {
            throw IoException(
                IoExceptionMessageConstant.mustHave8BitsPerComponent);
          }
          image.height = getShort().toDouble();
          image.width = getShort().toDouble();
          image.colorEncodingComponentsNumber = read();
          image.bpc = 8;
          break;
        } else if (markertype == UNSUPPORTED_MARKER) {
          throw IoException(IoExceptionMessageConstant.unsupportedJpegMarker);
        } else if (markertype != NOPARAM_MARKER) {
          int len = getShort();
          if (len >= 2) skip(len - 2);
        }
      }
    }
  }

  static int _getMarkerType(int marker) {
    if (VALID_MARKERS.contains(marker)) return VALID_MARKER;
    if (NOPARAM_MARKERS.contains(marker)) return NOPARAM_MARKER;
    if (UNSUPPORTED_MARKERS.contains(marker)) return UNSUPPORTED_MARKER;
    return NOT_A_MARKER;
  }
}
