import 'dart:io';
import 'dart:typed_data';
import 'package:dpdf/src/io/image/png_image_data.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

class PngParameters {
  final PngImageData image;
  int width = 0;
  int height = 0;
  int bitDepth = 0;
  int compressionMethod = 0;
  int filterMethod = 0;
  int interlaceMethod = 0;
  Map<String, Object> additional = {};
  Uint8List? imageData;
  Uint8List? smask;
  Uint8List? trans;
  BytesBuilder idat = BytesBuilder();
  int dpiX = 0;
  int dpiY = 0;
  double xyRatio = 0.0;
  bool genBWMask = false;
  bool palShades = false;
  int transRedGray = -1;
  int transGreen = -1;
  int transBlue = -1;
  int inputBands = 0;
  int bytesPerPixel = 0;
  String? intent;

  PngParameters(this.image);
}

class PngImageHelper {
  static const List<int> PNGID = [137, 80, 78, 71, 13, 10, 26, 10];
  static const String IHDR = "IHDR";
  static const String PLTE = "PLTE";
  static const String IDAT = "IDAT";
  static const String IEND = "IEND";
  static const String tRNS = "tRNS";
  static const String pHYs = "pHYs";
  static const String gAMA = "gAMA";
  static const String cHRM = "cHRM";
  static const String sRGB = "sRGB";
  static const String iCCP = "iCCP";

  static const int TRANSFERSIZE = 4096;
  static const int PNG_FILTER_NONE = 0;
  static const int PNG_FILTER_SUB = 1;
  static const int PNG_FILTER_UP = 2;
  static const int PNG_FILTER_AVERAGE = 3;
  static const int PNG_FILTER_PAETH = 4;

  static const List<String> intents = [
    "Perceptual",
    "RelativeColorimetric",
    "Saturation",
    "AbsoluteColorimetric"
  ];

  static void processImage(ImageData image) {
    if (image.getOriginalType() != ImageType.PNG) {
      throw Exception("PNG image expected");
    }
    try {
      if (image.getData() == null) {
        // image.loadData(); // Not implemented yet
      }
      Uint8List data = image.getData()!;
      image.imageSize = data.length;
      PngParameters png = PngParameters(image as PngImageData);
      _processPng(data, png);
    } catch (e) {
      throw IoException(IoExceptionMessageConstant.pngImageException);
    }
  }

  static void _processPng(Uint8List data, PngParameters png) {
    _readPng(data, png);
    int colorType = png.image.getColorType();

    // Pal shades and BW mask logic
    int pal0 = 0;
    int palIdx = 0;
    png.palShades = false;
    if (png.trans != null) {
      for (int k = 0; k < png.trans!.length; ++k) {
        int n = png.trans![k] & 0xff;
        if (n == 0) {
          ++pal0;
          palIdx = k;
        }
        if (n != 0 && n != 255) {
          png.palShades = true;
          break;
        }
      }
    }
    if ((colorType & 4) != 0) {
      png.palShades = true;
    }
    png.genBWMask = (!png.palShades && (pal0 > 1 || png.transRedGray >= 0));
    if (!png.palShades && !png.genBWMask && pal0 == 1) {
      png.additional["Mask"] = [palIdx, palIdx];
    }

    bool needDecode = (png.interlaceMethod == 1) ||
        (png.bitDepth == 16) ||
        ((colorType & 4) != 0) ||
        png.palShades ||
        png.genBWMask;

    switch (colorType) {
      case 0:
        png.inputBands = 1;
        break;
      case 2:
        png.inputBands = 3;
        break;
      case 3:
        png.inputBands = 1;
        break;
      case 4:
        png.inputBands = 2;
        break;
      case 6:
        png.inputBands = 4;
        break;
    }

    if (needDecode) {
      _decodeIdat(png);
    }

    int components = png.inputBands;
    if ((colorType & 4) != 0) {
      --components;
    }
    int bpc = png.bitDepth;
    if (bpc == 16) bpc = 8;

    if (png.imageData != null) {
      // RawImageHelper.updateRawImageParameters(...)
      png.image.width = png.width.toDouble();
      png.image.height = png.height.toDouble();
      png.image.colorEncodingComponentsNumber = components;
      png.image.bpc = bpc;
      png.image.data = png.imageData;
    } else {
      png.image.width = png.width.toDouble();
      png.image.height = png.height.toDouble();
      png.image.colorEncodingComponentsNumber = components;
      png.image.bpc = bpc;
      png.image.data = png.idat.toBytes();
      png.image.setDeflated(true);
      png.image.decodeParms = {
        "BitsPerComponent": png.bitDepth,
        "Predictor": 15,
        "Columns": png.width,
        "Colors":
            (png.image.isIndexed() || png.image.isGrayscaleImage()) ? 1 : 3
      };
    }

    if (png.intent != null) {
      png.additional["Intent"] = png.intent!;
    }
    // ICC profile set if exists
    png.image.setDpi(png.dpiX, png.dpiY);
    png.image.setXYRatio(png.xyRatio);
  }

  static void _readPng(Uint8List data, PngParameters png) {
    int offset = 0;
    for (int i = 0; i < PNGID.length; i++) {
      if (PNGID[i] != data[offset++]) {
        throw Exception("File is not a valid PNG");
      }
    }

    while (offset < data.length) {
      int len = _getInt(data, offset);
      offset += 4;
      String marker = _getString(data, offset, 4);
      offset += 4;

      if (len < 0 || !_checkMarker(marker)) {
        throw Exception("Corrupted PNG file");
      }

      if (marker == IDAT) {
        png.idat.add(data.sublist(offset, offset + len));
        offset += len;
      } else if (marker == tRNS) {
        switch (png.image.getColorType()) {
          case 0:
            if (len >= 2) {
              int gray = _getWord(data, offset);
              if (png.bitDepth == 16) {
                png.transRedGray = gray;
              } else {
                png.additional["Mask"] = [gray, gray];
              }
            }
            break;
          case 2:
            if (len >= 6) {
              int red = _getWord(data, offset);
              int green = _getWord(data, offset + 2);
              int blue = _getWord(data, offset + 4);
              if (png.bitDepth == 16) {
                png.transRedGray = red;
                png.transGreen = green;
                png.transBlue = blue;
              } else {
                png.additional["Mask"] = [red, red, green, green, blue, blue];
              }
            }
            break;
          case 3:
            if (len > 0) {
              png.trans = data.sublist(offset, offset + len);
            }
            break;
        }
        offset += len;
      } else if (marker == IHDR) {
        png.width = _getInt(data, offset);
        png.height = _getInt(data, offset + 4);
        png.bitDepth = data[offset + 8];
        png.image.setColorType(data[offset + 9]);
        png.compressionMethod = data[offset + 10];
        png.filterMethod = data[offset + 11];
        png.interlaceMethod = data[offset + 12];
        offset += len;
      } else if (marker == PLTE) {
        if (png.image.isIndexed()) {
          png.image.setColorPalette(data.sublist(offset, offset + len));
        }
        offset += len;
      } else if (marker == pHYs) {
        int dx = _getInt(data, offset);
        int dy = _getInt(data, offset + 4);
        int unit = data[offset + 8];
        if (unit == 1) {
          png.dpiX = (dx * 0.0254 + 0.5).toInt();
          png.dpiY = (dy * 0.0254 + 0.5).toInt();
        } else {
          if (dy != 0) {
            png.xyRatio = dx / dy;
          }
        }
        offset += len;
      } else if (marker == gAMA) {
        int gm = _getInt(data, offset);
        if (gm != 0) {
          png.image.setGamma(100000.0 / gm);
          // if (!png.image.isHasCHRM()) ...
        }
        offset += len;
      } else if (marker == sRGB) {
        int ri = data[offset];
        if (ri < PngImageHelper.intents.length) {
          png.intent = PngImageHelper.intents[ri];
        }
        png.image.setGamma(2.2);
        offset += len;
      } else if (marker == IEND) {
        break;
      } else {
        // Skip other markers for now
        offset += len;
      }
      offset += 4; // Skip CRC
    }
  }

  static int _getInt(Uint8List data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  static int _getWord(Uint8List data, int offset) {
    return (data[offset] << 8) | data[offset + 1];
  }

  static void _decodeIdat(PngParameters png) {
    int nbitDepth = png.bitDepth;
    if (nbitDepth == 16) nbitDepth = 8;

    int size = -1;
    png.bytesPerPixel = (png.bitDepth == 16) ? 2 : 1;
    int colorType = png.image.getColorType();

    switch (colorType) {
      case 0:
        size = ((nbitDepth * png.width + 7) ~/ 8) * png.height;
        break;
      case 2:
        size = png.width * 3 * png.height;
        png.bytesPerPixel *= 3;
        break;
      case 3:
        if (png.interlaceMethod == 1) {
          size = ((nbitDepth * png.width + 7) ~/ 8) * png.height;
        }
        png.bytesPerPixel = 1;
        break;
      case 4:
        size = png.width * png.height;
        png.bytesPerPixel *= 2;
        break;
      case 6:
        size = png.width * 3 * png.height;
        png.bytesPerPixel *= 4;
        break;
    }

    if (size >= 0) {
      png.imageData = Uint8List(size);
    }
    if (png.palShades) {
      png.smask = Uint8List(png.width * png.height);
    } else if (png.genBWMask) {
      png.smask = Uint8List(((png.width + 7) ~/ 8) * png.height);
    }

    Uint8List compressed = png.idat.toBytes();
    Uint8List decompressed = Uint8List.fromList(zlib.decode(compressed));
    _decodePassInternal(decompressed, png);
  }

  static void _decodePassInternal(Uint8List data, PngParameters png) {
    // Simple stateful reader or just wrap in a stream-like way
    // For now, let's just use an offset-based reader
    int offset = 0;

    if (png.interlaceMethod != 1) {
      offset =
          _decodePass(data, offset, 0, 0, 1, 1, png.width, png.height, png);
    } else {
      offset = _decodePass(data, offset, 0, 0, 8, 8, (png.width + 7) ~/ 8,
          (png.height + 7) ~/ 8, png);
      offset = _decodePass(data, offset, 4, 0, 8, 8, (png.width + 3) ~/ 8,
          (png.height + 7) ~/ 8, png);
      offset = _decodePass(data, offset, 0, 4, 4, 8, (png.width + 3) ~/ 4,
          (png.height + 3) ~/ 8, png);
      offset = _decodePass(data, offset, 2, 0, 4, 4, (png.width + 1) ~/ 4,
          (png.height + 3) ~/ 4, png);
      offset = _decodePass(data, offset, 0, 2, 2, 4, (png.width + 1) ~/ 2,
          (png.height + 1) ~/ 4, png);
      offset = _decodePass(
          data, offset, 1, 0, 2, 2, png.width ~/ 2, (png.height + 1) ~/ 2, png);
      _decodePass(data, offset, 0, 1, 1, 2, png.width, png.height ~/ 2, png);
    }
  }

  static int _decodePass(Uint8List data, int offset, int xOffset, int yOffset,
      int xStep, int yStep, int passWidth, int passHeight, PngParameters png) {
    if (passWidth == 0 || passHeight == 0) return offset;

    int bytesPerRow = (png.inputBands * passWidth * png.bitDepth + 7) ~/ 8;
    Uint8List curr = Uint8List(bytesPerRow);
    Uint8List prior = Uint8List(bytesPerRow);

    int dstY = yOffset;
    for (int srcY = 0; srcY < passHeight; srcY++, dstY += yStep) {
      if (offset >= data.length) break;
      int filter = data[offset++];
      curr.setRange(0, bytesPerRow, data.sublist(offset, offset + bytesPerRow));
      offset += bytesPerRow;

      switch (filter) {
        case PNG_FILTER_NONE:
          break;
        case PNG_FILTER_SUB:
          _decodeSubFilter(curr, bytesPerRow, png.bytesPerPixel);
          break;
        case PNG_FILTER_UP:
          _decodeUpFilter(curr, prior, bytesPerRow);
          break;
        case PNG_FILTER_AVERAGE:
          _decodeAverageFilter(curr, prior, bytesPerRow, png.bytesPerPixel);
          break;
        case PNG_FILTER_PAETH:
          _decodePaethFilter(curr, prior, bytesPerRow, png.bytesPerPixel);
          break;
        default:
          throw IoException(IoExceptionMessageConstant.unknownPngFilter);
      }

      _processPixels(curr, xOffset, xStep, dstY, passWidth, png);
      prior.setRange(0, bytesPerRow, curr);
    }
    return offset;
  }

  static void _decodeSubFilter(Uint8List curr, int count, int bpp) {
    for (int i = bpp; i < count; i++) {
      curr[i] = (curr[i] + curr[i - bpp]) & 0xff;
    }
  }

  static void _decodeUpFilter(Uint8List curr, Uint8List prior, int count) {
    for (int i = 0; i < count; i++) {
      curr[i] = (curr[i] + prior[i]) & 0xff;
    }
  }

  static void _decodeAverageFilter(
      Uint8List curr, Uint8List prior, int count, int bpp) {
    for (int i = 0; i < bpp; i++) {
      curr[i] = (curr[i] + (prior[i] ~/ 2)) & 0xff;
    }
    for (int i = bpp; i < count; i++) {
      curr[i] = (curr[i] + ((curr[i - bpp] + prior[i]) ~/ 2)) & 0xff;
    }
  }

  static void _decodePaethFilter(
      Uint8List curr, Uint8List prior, int count, int bpp) {
    for (int i = 0; i < bpp; i++) {
      curr[i] = (curr[i] + prior[i]) & 0xff;
    }
    for (int i = bpp; i < count; i++) {
      int a = curr[i - bpp];
      int b = prior[i];
      int c = prior[i - bpp];

      int p = a + b - c;
      int pa = (p - a).abs();
      int pb = (p - b).abs();
      int pc = (p - c).abs();

      int pr;
      if (pa <= pb && pa <= pc) {
        pr = a;
      } else if (pb <= pc) {
        pr = b;
      } else {
        pr = c;
      }
      curr[i] = (curr[i] + pr) & 0xff;
    }
  }

  static void _processPixels(Uint8List curr, int xOffset, int step, int y,
      int width, PngParameters png) {
    int colorType = png.image.getColorType();
    Int32List outPixel = _getPixelArray(curr, png);
    int sizes = 0;
    switch (colorType) {
      case 0:
      case 3:
      case 4:
        sizes = 1;
        break;
      case 2:
      case 6:
        sizes = 3;
        break;
    }
    if (png.imageData != null) {
      int dstX = xOffset;
      int yStride =
          (sizes * png.width * (png.bitDepth == 16 ? 8 : png.bitDepth) + 7) ~/
              8;
      for (int srcX = 0; srcX < width; srcX++) {
        _setPixel(png.imageData!, outPixel, png.inputBands * srcX, sizes, dstX,
            y, png.bitDepth, yStride);
        dstX += step;
      }
    }

    if (png.palShades) {
      if ((colorType & 4) != 0) {
        if (png.bitDepth == 16) {
          for (int k = 0; k < width; ++k) {
            outPixel[k * png.inputBands + sizes] =
                (outPixel[k * png.inputBands + sizes] >> 8) & 0xff;
          }
        }
        int yStride = png.width;
        int dstX = xOffset;
        for (int srcX = 0; srcX < width; srcX++) {
          _setPixel(png.smask!, outPixel, png.inputBands * srcX + sizes, 1,
              dstX, y, 8, yStride);
          dstX += step;
        }
      } else {
        // colorType 3
        int yStride = png.width;
        Int32List v = Int32List(1);
        int dstX = xOffset;
        for (int srcX = 0; srcX < width; srcX++) {
          int idx = outPixel[srcX];
          if (png.trans != null && idx < png.trans!.length) {
            v[0] = png.trans![idx];
          } else {
            v[0] = 255;
          }
          _setPixel(png.smask!, v, 0, 1, dstX, y, 8, yStride);
          dstX += step;
        }
      }
    } else if (png.genBWMask) {
      switch (colorType) {
        case 3:
          int yStride = (png.width + 7) ~/ 8;
          Int32List v = Int32List(1);
          int dstX = xOffset;
          for (int srcX = 0; srcX < width; srcX++) {
            int idx = outPixel[srcX];
            v[0] = ((png.trans != null &&
                    idx < png.trans!.length &&
                    png.trans![idx] == 0)
                ? 1
                : 0);
            _setPixel(png.smask!, v, 0, 1, dstX, y, 1, yStride);
            dstX += step;
          }
          break;
        case 0:
          int yStride = (png.width + 7) ~/ 8;
          Int32List v = Int32List(1);
          int dstX = xOffset;
          for (int srcX = 0; srcX < width; srcX++) {
            int g = outPixel[srcX];
            v[0] = (g == png.transRedGray ? 1 : 0);
            _setPixel(png.smask!, v, 0, 1, dstX, y, 1, yStride);
            dstX += step;
          }
          break;
        case 2:
          int yStride = (png.width + 7) ~/ 8;
          Int32List v = Int32List(1);
          int dstX = xOffset;
          for (int srcX = 0; srcX < width; srcX++) {
            int markRed = png.inputBands * srcX;
            v[0] = (outPixel[markRed] == png.transRedGray &&
                    outPixel[markRed + 1] == png.transGreen &&
                    outPixel[markRed + 2] == png.transBlue
                ? 1
                : 0);
            _setPixel(png.smask!, v, 0, 1, dstX, y, 1, yStride);
            dstX += step;
          }
          break;
      }
    }
  }

  static Int32List _getPixelArray(Uint8List curr, PngParameters png) {
    Int32List outPixel = Int32List(png.inputBands * png.width);
    int bitDepth = png.bitDepth;
    if (bitDepth == 8) {
      for (int i = 0; i < curr.length; i++) {
        outPixel[i] = curr[i] & 0xff;
      }
    } else if (bitDepth == 16) {
      for (int i = 0; i < curr.length ~/ 2; i++) {
        outPixel[i] = ((curr[i * 2] & 0xff) << 8) + (curr[i * 2 + 1] & 0xff);
      }
    } else {
      int pos = 0;
      int nCr = 8 ~/ bitDepth;
      for (int i = 0; i < curr.length; i++) {
        for (int j = nCr - 1; j >= 0; j--) {
          if (pos < outPixel.length) {
            outPixel[pos++] =
                (curr[i] >> (bitDepth * j)) & ((1 << bitDepth) - 1);
          }
        }
      }
    }
    return outPixel;
  }

  static void _setPixel(Uint8List image, Int32List data, int offset, int size,
      int x, int y, int bitDepth, int bytesPerRow) {
    if (bitDepth == 8) {
      int pos = bytesPerRow * y + x * size;
      for (int i = 0; i < size; i++) {
        image[pos + i] = data[offset + i] & 0xff;
      }
    } else if (bitDepth == 16) {
      int pos = bytesPerRow * y + x * size;
      for (int i = 0; i < size; i++) {
        image[pos + i] = (data[offset + i] >> 8) & 0xff;
      }
    } else {
      int pos = bytesPerRow * y + x ~/ (8 ~/ bitDepth);
      int shift = bitDepth * (8 ~/ bitDepth - 1 - (x % (8 ~/ bitDepth)));
      image[pos] |= (data[offset] & ((1 << bitDepth) - 1)) << shift;
    }
  }

  static String _getString(Uint8List data, int offset, int len) {
    return String.fromCharCodes(data.sublist(offset, offset + len));
  }

  static bool _checkMarker(String s) {
    if (s.length != 4) return false;
    for (int i = 0; i < 4; i++) {
      int c = s.codeUnitAt(i);
      if (!((c >= 97 && c <= 122) || (c >= 65 && c <= 90))) return false;
    }
    return true;
  }
}
