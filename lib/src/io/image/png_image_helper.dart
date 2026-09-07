import '../../platform/compression.dart';
import 'dart:typed_data';
import 'package:dpdf/src/io/image/png_image_data.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'raw_image_data.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

class PngParameters {
  final CraftPngImageData image;
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

class CraftPngImageHelper {
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

  static void processImage(CraftImageData image) {
    if (image.getOriginalType() != CraftImageType.PNG) {
      throw Exception("PNG image expected");
    }
    try {
      if (image.getData() == null) {
        // image.loadData(); // Not implemented yet
      }
      Uint8List data = image.getData()!;
      image.imageSize = data.length;
      PngParameters png = PngParameters(image as CraftPngImageData);
      _processPng(data, png);
    } catch (e) {
      throw IoException(CraftIoExceptionMessageConstant.pngImageException);
    }
  }

  static void _processPng(Uint8List data, PngParameters png) {
    _readPng(data, png);
    int colorType = png.image.getColorType();

    final opacity = png.trans ?? Uint8List(0);
    final transparentIndices = <int>[
      for (var index = 0; index < opacity.length; index++)
        if (opacity[index] == 0) index
    ];
    png.palShades = colorType == 4 ||
        colorType == 6 ||
        opacity.any((alpha) => alpha > 0 && alpha < 255);
    png.genBWMask = !png.palShades &&
        (transparentIndices.length > 1 || png.transRedGray >= 0);
    if (!png.palShades && !png.genBWMask && transparentIndices.length == 1) {
      png.additional['Mask'] = List<int>.filled(2, transparentIndices.single);
    }

    png.inputBands = switch (colorType) {
      0 || 3 => 1,
      2 => 3,
      4 => 2,
      6 => 4,
      _ => throw IoException('PNG color model is unsupported.'),
    };
    final hasSeparateMask = png.palShades || png.genBWMask;
    final transformsSamples = png.bitDepth > 8 || png.interlaceMethod != 0;
    if (hasSeparateMask || transformsSamples) {
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

    if (png.smask != null) {
      final mask = CraftRawImageData.fromBytes(png.smask!, CraftImageType.RAW)
        ..width = png.width.toDouble()
        ..height = png.height.toDouble()
        ..bpc = png.palShades ? 8 : 1
        ..colorEncodingComponentsNumber = 1;
      mask.makeMask();
      png.image.setImageMask(mask);
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
        if (ri < CraftPngImageHelper.intents.length) {
          png.intent = CraftPngImageHelper.intents[ri];
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
    final indexed = png.image.getColorType() == 3;
    final alphaChannel =
        png.image.getColorType() == 4 || png.image.getColorType() == 6;
    final outputBands = png.inputBands - (alphaChannel ? 1 : 0);
    final outputDepth = png.bitDepth > 8 ? 8 : png.bitDepth;
    png.bytesPerPixel = (png.inputBands * png.bitDepth + 7) ~/ 8;

    // Indexed noninterlaced samples may remain in their original IDAT stream
    // while the decoded indices supply a separate transparency mask.
    if (!indexed || png.interlaceMethod != 0) {
      final rowBytes = (png.width * outputBands * outputDepth + 7) ~/ 8;
      png.imageData = Uint8List(rowBytes * png.height);
    }
    final maskDepth = png.palShades ? 8 : (png.genBWMask ? 1 : 0);
    if (maskDepth != 0) {
      png.smask = Uint8List(((png.width * maskDepth + 7) ~/ 8) * png.height);
    }
    _decodePassInternal(
        Uint8List.fromList(zlib.decode(png.idat.toBytes())), png);
  }

  static void _decodePassInternal(Uint8List data, PngParameters png) {
    final passes = png.interlaceMethod == 0
        ? const [(0, 0, 1, 1)]
        : const [
            (0, 0, 8, 8),
            (4, 0, 8, 8),
            (0, 4, 4, 8),
            (2, 0, 4, 4),
            (0, 2, 2, 4),
            (1, 0, 2, 2),
            (0, 1, 1, 2)
          ];
    var cursor = 0;
    for (final (left, top, across, down) in passes) {
      if (left >= png.width || top >= png.height) continue;
      final columns = 1 + (png.width - left - 1) ~/ across;
      final rows = 1 + (png.height - top - 1) ~/ down;
      cursor = _decodePass(
          data, cursor, left, top, across, down, columns, rows, png);
    }
    if (cursor != data.length) {
      throw IoException('PNG raster contains bytes beyond its scanlines.');
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
      if (data.length - offset < bytesPerRow + 1) {
        throw IoException('PNG raster ends before a complete scanline.');
      }
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
          throw IoException(CraftIoExceptionMessageConstant.unknownPngFilter);
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
    final model = png.image.getColorType();
    final channels = model == 2 || model == 6 ? 3 : 1;
    final values = _getPixelArray(curr, png);
    final depth = png.bitDepth == 16 ? 8 : png.bitDepth;
    final stride = (png.width * channels * depth + 7) ~/ 8;
    final maskValue = Int32List(1);
    for (var pixel = 0; pixel < width; pixel++) {
      final x = xOffset + pixel * step;
      final source = pixel * png.inputBands;
      if (png.imageData != null) {
        _setPixel(png.imageData!, values, source, channels, x, y, png.bitDepth,
            stride);
      }
      if (png.smask == null) continue;
      final index = values[source];
      final paletteAlpha = png.trans != null && index < png.trans!.length
          ? png.trans![index]
          : 255;
      if (png.palShades) {
        maskValue[0] = model == 4 || model == 6
            ? values[source + channels] >> (png.bitDepth == 16 ? 8 : 0)
            : paletteAlpha;
        _setPixel(png.smask!, maskValue, 0, 1, x, y, 8, png.width);
      } else {
        final transparent = switch (model) {
          3 => paletteAlpha == 0,
          0 => index == png.transRedGray,
          2 => index == png.transRedGray &&
              values[source + 1] == png.transGreen &&
              values[source + 2] == png.transBlue,
          _ => false,
        };
        maskValue[0] = transparent ? 1 : 0;
        _setPixel(png.smask!, maskValue, 0, 1, x, y, 1, (png.width + 7) ~/ 8);
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
