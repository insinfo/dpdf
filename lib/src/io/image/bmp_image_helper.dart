import 'dart:typed_data';

import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';
import 'package:dpdf/src/io/image/bmp_image_data.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/io/image/raw_image_helper.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'package:dpdf/src/io/font/pdf_encodings.dart';

import 'package:dpdf/src/layout/properties/image_type.dart';

class BmpImageHelper {
  // BMP Image types
  static const int version2_1bit = 0;
  static const int version2_4bit = 1;
  static const int version2_8bit = 2;
  static const int version2_24bit = 3;
  static const int version3_1bit = 4;
  static const int version3_4bit = 5;
  static const int version3_8bit = 6;
  static const int version3_24bit = 7;
  static const int version3_nt_16bit = 8;
  static const int version3_nt_32bit = 9;
  static const int version4_1bit = 10;
  static const int version4_4bit = 11;
  static const int version4_8bit = 12;
  static const int version4_16bit = 13;
  static const int version4_24bit = 14;
  static const int version4_32bit = 15;

  // Color space types
  static const int lcsCalibratedRgb = 0;
  static const int lcsSRgb = 1;
  static const int lcsCmyk = 2;

  // Compression Types
  static const int biRgb = 0;
  static const int biRle8 = 1;
  static const int biRle4 = 2;
  static const int biBitfields = 3;

  /// Process the passed Image data as a BMP image.
  static void processImage(ImageData image) {
    if (image.getOriginalType() != ImageType.BMP) {
      throw ArgumentError("BMP image expected");
    }

    try {
      if (image.getData() == null) {
        // In Dart we typically expect data to be present if it wasn't loaded via URL in a way that deferred loading.
        // If image.url is set and data is null, we might need a way to load it, but usually this is handled before calling helper.
        throw IoException("Image data is null");
      }

      final bmp = BmpParameters(image as BmpImageData);
      // Using RandomAccessFileOrArray instead of Stream for easier seeking and LE reading
      final stream = RandomAccessFileOrArray(image.getData()!);

      image.imageSize = image.getData()!.length;

      _process(bmp, stream);

      if (_getImage(bmp)) {
        image.setWidth(bmp.width.toDouble());
        image.setHeight(bmp.height.toDouble());
        final dpiX = (bmp.xPelsPerMeter * 0.0254 + 0.5).toInt();
        final dpiY = (bmp.yPelsPerMeter * 0.0254 + 0.5).toInt();
        image.setDpi(dpiX, dpiY);
      }

      RawImageHelper.updateImageAttributes(bmp.image, bmp.additional);

      stream.close();
    } catch (e) {
      if (e is IoException) rethrow;
      throw IoException(IoExceptionMessageConstant.bmpImageException, e);
    }
  }

  static void _process(BmpParameters bmp, RandomAccessFileOrArray stream) {
    bmp.inputStream = stream;
    if (!bmp.image.isNoHeader()) {
      // Start File Header
      if (!(stream.readUnsignedByte() == 0x42 &&
          stream.readUnsignedByte() == 0x4D)) {
        // 'B' 'M'
        throw IoException(
            IoExceptionMessageConstant.invalidMagicValueForBmpFileMustBeBm);
      }
      // Read file size
      bmp.bitmapFileSize = stream.readUnsignedIntLE();
      // Read the two reserved fields
      stream.readShortLE();
      stream.readShortLE();
      // Offset to the bitmap from the beginning
      bmp.bitmapOffset = stream.readUnsignedIntLE();
    }

    // End File Header
    // Start BitmapCoreHeader
    int size = stream.readUnsignedIntLE(); // DWord is unsigned int
    if (size == 12) {
      bmp.width = stream.readUnsignedShortLE();
      bmp.height = stream.readUnsignedShortLE();
    } else {
      bmp.width = stream.readIntLE(); // Long is signed 32-bit int in C#
      bmp.height = stream.readIntLE();
    }

    int planes = stream.readUnsignedShortLE();
    bmp.bitsPerPixel = stream.readUnsignedShortLE();
    bmp.properties["color_planes"] = planes;
    bmp.properties["bits_per_pixel"] = bmp.bitsPerPixel;

    bmp.numBands = 3;
    if (bmp.bitmapOffset == 0) {
      bmp.bitmapOffset = size;
    }

    if (size == 12) {
      // Windows 2.x and OS/2 1.x
      bmp.properties["bmp_version"] = "BMP v. 2.x";
      if (bmp.bitsPerPixel == 1) {
        bmp.imageType = version2_1bit;
      } else if (bmp.bitsPerPixel == 4) {
        bmp.imageType = version2_4bit;
      } else if (bmp.bitsPerPixel == 8) {
        bmp.imageType = version2_8bit;
      } else if (bmp.bitsPerPixel == 24) {
        bmp.imageType = version2_24bit;
      }

      int numberOfEntries = ((bmp.bitmapOffset - 14 - size) / 3).toInt();
      int sizeOfPalette = numberOfEntries * 3;
      if (bmp.bitmapOffset == size) {
        switch (bmp.imageType) {
          case version2_1bit:
            sizeOfPalette = 2 * 3;
            break;
          case version2_4bit:
            sizeOfPalette = 16 * 3;
            break;
          case version2_8bit:
            sizeOfPalette = 256 * 3;
            break;
          case version2_24bit:
            sizeOfPalette = 0;
            break;
        }
        bmp.bitmapOffset = size + sizeOfPalette;
      }
      _readPalette(sizeOfPalette, bmp);
    } else {
      bmp.compression = stream.readUnsignedIntLE();
      bmp.imageSize = stream.readUnsignedIntLE();
      bmp.xPelsPerMeter = stream.readIntLE(); // Long
      bmp.yPelsPerMeter = stream.readIntLE();
      int colorsUsed = stream.readUnsignedIntLE(); // DWord
      int colorsImportant = stream.readUnsignedIntLE();

      switch (bmp.compression) {
        case biRgb:
          bmp.properties["compression"] = "BI_RGB";
          break;
        case biRle8:
          bmp.properties["compression"] = "BI_RLE8";
          break;
        case biRle4:
          bmp.properties["compression"] = "BI_RLE4";
          break;
        case biBitfields:
          bmp.properties["compression"] = "BI_BITFIELDS";
          break;
      }

      bmp.properties["x_pixels_per_meter"] = bmp.xPelsPerMeter;
      bmp.properties["y_pixels_per_meter"] = bmp.yPelsPerMeter;
      bmp.properties["colors_used"] = colorsUsed;
      bmp.properties["colors_important"] = colorsImportant;

      if (size == 40 || size == 52 || size == 56) {
        int sizeOfPalette = 0;
        // Windows 3.x and Windows NT
        switch (bmp.compression) {
          case biRgb:
          case biRle8:
          case biRle4:
            if (bmp.bitsPerPixel == 1) {
              bmp.imageType = version3_1bit;
            } else if (bmp.bitsPerPixel == 4) {
              bmp.imageType = version3_4bit;
            } else if (bmp.bitsPerPixel == 8) {
              bmp.imageType = version3_8bit;
            } else if (bmp.bitsPerPixel == 24) {
              bmp.imageType = version3_24bit;
            } else if (bmp.bitsPerPixel == 16) {
              bmp.imageType = version3_nt_16bit;
              bmp.redMask = 0x7C00;
              bmp.greenMask = 0x3E0;
              bmp.blueMask = 0x1F;
              bmp.properties["red_mask"] = bmp.redMask;
              bmp.properties["green_mask"] = bmp.greenMask;
              bmp.properties["blue_mask"] = bmp.blueMask;
            } else if (bmp.bitsPerPixel == 32) {
              bmp.imageType = version3_nt_32bit;
              bmp.redMask = 0x00FF0000;
              bmp.greenMask = 0x0000FF00;
              bmp.blueMask = 0x000000FF;
              bmp.properties["red_mask"] = bmp.redMask;
              bmp.properties["green_mask"] = bmp.greenMask;
              bmp.properties["blue_mask"] = bmp.blueMask;
            }

            if (size >= 52) {
              bmp.redMask = stream.readUnsignedIntLE();
              bmp.greenMask = stream.readUnsignedIntLE();
              bmp.blueMask = stream.readUnsignedIntLE();
              bmp.properties["red_mask"] = bmp.redMask;
              bmp.properties["green_mask"] = bmp.greenMask;
              bmp.properties["blue_mask"] = bmp.blueMask;
            }

            if (size == 56) {
              bmp.alphaMask = stream.readUnsignedIntLE();
              bmp.properties["alpha_mask"] = bmp.alphaMask;
            }

            int numberOfEntries = ((bmp.bitmapOffset - 14 - size) / 4).toInt();
            sizeOfPalette = numberOfEntries * 4;
            if (bmp.bitmapOffset == size) {
              switch (bmp.imageType) {
                case version3_1bit:
                  sizeOfPalette = (colorsUsed == 0 ? 2 : colorsUsed) * 4;
                  break;
                case version3_4bit:
                  sizeOfPalette = (colorsUsed == 0 ? 16 : colorsUsed) * 4;
                  break;
                case version3_8bit:
                  sizeOfPalette = (colorsUsed == 0 ? 256 : colorsUsed) * 4;
                  break;
                default:
                  sizeOfPalette = 0;
                  break;
              }
              bmp.bitmapOffset = size + sizeOfPalette;
            }
            _readPalette(sizeOfPalette, bmp);
            bmp.properties["bmp_version"] = "BMP v. 3.x";
            break;

          case biBitfields:
            if (bmp.bitsPerPixel == 16) {
              bmp.imageType = version3_nt_16bit;
            } else if (bmp.bitsPerPixel == 32) {
              bmp.imageType = version3_nt_32bit;
            }
            bmp.redMask = stream.readUnsignedIntLE();
            bmp.greenMask = stream.readUnsignedIntLE();
            bmp.blueMask = stream.readUnsignedIntLE();

            if (size == 56) {
              bmp.alphaMask = stream.readUnsignedIntLE();
              bmp.properties["alpha_mask"] = bmp.alphaMask;
            }
            bmp.properties["red_mask"] = bmp.redMask;
            bmp.properties["green_mask"] = bmp.greenMask;
            bmp.properties["blue_mask"] = bmp.blueMask;

            if (colorsUsed != 0) {
              sizeOfPalette = colorsUsed * 4;
              _readPalette(sizeOfPalette, bmp);
            }
            bmp.properties["bmp_version"] = "BMP v. 3.x NT";
            break;

          default:
            throw IoException(
                IoExceptionMessageConstant.invalidBmpFileCompression);
        }
      } else if (size == 108) {
        // Windows 4.x BMP
        bmp.properties["bmp_version"] = "BMP v. 4.x";
        bmp.redMask = stream.readUnsignedIntLE();
        bmp.greenMask = stream.readUnsignedIntLE();
        bmp.blueMask = stream.readUnsignedIntLE();
        bmp.alphaMask = stream.readUnsignedIntLE();
        int csType = stream.readUnsignedIntLE(); // DWord
        stream.readIntLE();
        stream.readIntLE();
        stream.readIntLE();
        stream.readIntLE();
        stream.readIntLE();
        stream.readIntLE();
        stream.readIntLE();
        stream.readIntLE();
        stream.readIntLE();
        stream.readUnsignedIntLE();
        stream.readUnsignedIntLE();
        stream.readUnsignedIntLE();

        if (bmp.bitsPerPixel == 1) {
          bmp.imageType = version4_1bit;
        } else if (bmp.bitsPerPixel == 4) {
          bmp.imageType = version4_4bit;
        } else if (bmp.bitsPerPixel == 8) {
          bmp.imageType = version4_8bit;
        } else if (bmp.bitsPerPixel == 16) {
          bmp.imageType = version4_16bit;
          if (bmp.compression == biRgb) {
            bmp.redMask = 0x7C00;
            bmp.greenMask = 0x3E0;
            bmp.blueMask = 0x1F;
          }
        } else if (bmp.bitsPerPixel == 24) {
          bmp.imageType = version4_24bit;
        } else if (bmp.bitsPerPixel == 32) {
          bmp.imageType = version4_32bit;
          if (bmp.compression == biRgb) {
            bmp.redMask = 0x00FF0000;
            bmp.greenMask = 0x0000FF00;
            bmp.blueMask = 0x000000FF;
          }
        }

        bmp.properties["red_mask"] = bmp.redMask;
        bmp.properties["green_mask"] = bmp.greenMask;
        bmp.properties["blue_mask"] = bmp.blueMask;
        bmp.properties["alpha_mask"] = bmp.alphaMask;

        int numberOfEntries = ((bmp.bitmapOffset - 14 - size) / 4).toInt();
        int sizeOfPalette = numberOfEntries * 4;
        if (bmp.bitmapOffset == size) {
          switch (bmp.imageType) {
            case version4_1bit:
              sizeOfPalette = (colorsUsed == 0 ? 2 : colorsUsed) * 4;
              break;
            case version4_4bit:
              sizeOfPalette = (colorsUsed == 0 ? 16 : colorsUsed) * 4;
              break;
            case version4_8bit:
              sizeOfPalette = (colorsUsed == 0 ? 256 : colorsUsed) * 4;
              break;
            default:
              sizeOfPalette = 0;
              break;
          }
          bmp.bitmapOffset = size + sizeOfPalette;
        }
        _readPalette(sizeOfPalette, bmp);

        if (csType == lcsCalibratedRgb) {
          throw IoException("Not implemented yet.");
        } else if (csType == lcsSRgb) {
          bmp.properties["color_space"] = "LCS_sRGB";
        } else if (csType == lcsCmyk) {
          bmp.properties["color_space"] = "LCS_CMYK";
          throw IoException("Not implemented yet.");
        }
      } else {
        bmp.properties["bmp_version"] = "BMP v. 5.x";
        throw IoException("Not implemented yet.");
      }
    }

    if (bmp.height > 0) {
      bmp.isBottomUp = true;
    } else {
      bmp.isBottomUp = false;
      bmp.height = bmp.height.abs();
    }

    if (bmp.bitsPerPixel == 1 ||
        bmp.bitsPerPixel == 4 ||
        bmp.bitsPerPixel == 8) {
      bmp.numBands = 1;
      // Logic for IndexColorModel creation skipped in Dart port as we just store raw data and attributes?
      // C# does create r,g,b arrays but then doesn't use them explicitly to set `image.SetPalette` here?
      // It seems C# re-reads palette in IndexedModel.
    } else if (bmp.bitsPerPixel == 16) {
      bmp.numBands = 3;
    } else if (bmp.bitsPerPixel == 32) {
      bmp.numBands = bmp.alphaMask == 0 ? 3 : 4;
    } else {
      bmp.numBands = 3;
    }
  }

  static void _readPalette(int sizeOfPalette, BmpParameters bmp) {
    if (sizeOfPalette == 0) return;
    bmp.palette = Uint8List(sizeOfPalette);
    // In C#, JRead reads into array. Here we read from RAF.
    // RAF is at current position.
    // We need to read sizeOfPalette bytes.
    bmp.inputStream!.readFully(bmp.palette!);
    bmp.properties["palette"] = bmp.palette;
  }

  static bool _getImage(BmpParameters bmp) {
    switch (bmp.imageType) {
      case version2_1bit:
        _read1Bit(3, bmp);
        return true;
      case version2_4bit:
        _read4Bit(3, bmp);
        return true;
      case version2_8bit:
        _read8Bit(3, bmp);
        return true;
      case version2_24bit:
        Uint8List bdata = Uint8List(bmp.width * bmp.height * 3);
        _read24Bit(bdata, bmp);
        RawImageHelper.updateRawImageParameters(
            bmp.image, bmp.width, bmp.height, 3, 8, bdata);
        return true;
      case version3_1bit:
        _read1Bit(4, bmp);
        return true;
      case version3_4bit:
        if (bmp.compression == biRgb) {
          _read4Bit(4, bmp);
        } else if (bmp.compression == biRle4) {
          _readRle4(bmp);
        } else {
          throw IoException(
              IoExceptionMessageConstant.invalidBmpFileCompression);
        }
        return true;
      case version3_8bit:
        if (bmp.compression == biRgb) {
          _read8Bit(4, bmp);
        } else if (bmp.compression == biRle8) {
          _readRle8(bmp);
        } else {
          throw IoException(
              IoExceptionMessageConstant.invalidBmpFileCompression);
        }
        return true;
      case version3_24bit:
        Uint8List bdata = Uint8List(bmp.width * bmp.height * 3);
        _read24Bit(bdata, bmp);
        RawImageHelper.updateRawImageParameters(
            bmp.image, bmp.width, bmp.height, 3, 8, bdata);
        return true;
      case version3_nt_16bit:
        _read1632Bit(false, bmp);
        return true;
      case version3_nt_32bit:
        _read1632Bit(true, bmp);
        return true;
      case version4_1bit:
        _read1Bit(4, bmp);
        return true;
      case version4_4bit:
        if (bmp.compression == biRgb) {
          _read4Bit(4, bmp);
        } else if (bmp.compression == biRle4) {
          _readRle4(bmp);
        } else {
          throw IoException(
              IoExceptionMessageConstant.invalidBmpFileCompression);
        }
        return true;
      case version4_8bit:
        if (bmp.compression == biRgb) {
          _read8Bit(4, bmp);
        } else if (bmp.compression == biRle8) {
          _readRle8(bmp);
        } else {
          throw IoException(
              IoExceptionMessageConstant.invalidBmpFileCompression);
        }
        return true;
      case version4_16bit:
        _read1632Bit(false, bmp);
        return true;
      case version4_24bit:
        Uint8List bdata = Uint8List(bmp.width * bmp.height * 3);
        _read24Bit(bdata, bmp);
        RawImageHelper.updateRawImageParameters(
            bmp.image, bmp.width, bmp.height, 3, 8, bdata);
        return true;
      case version4_32bit:
        _read1632Bit(true, bmp);
        return true;
    }
    return false;
  }

  static void _read1Bit(int paletteEntries, BmpParameters bmp) {
    int bytesPerScanline = (bmp.width / 8.0).ceil();
    int padding = 0;
    int remainder = bytesPerScanline % 4;
    if (remainder != 0) {
      padding = 4 - remainder;
    }
    int imSize = (bytesPerScanline + padding) * bmp.height;
    Uint8List values = Uint8List(imSize);
    bmp.inputStream!.readFully(values);

    Uint8List bdata = Uint8List((bmp.width + 7) ~/ 8 * bmp.height);

    if (bmp.isBottomUp) {
      for (int i = 0; i < bmp.height; i++) {
        // Array.Copy(values, imSize - (i + 1) * (bytesPerScanline + padding), bdata, i * bytesPerScanline, bytesPerScanline)
        int srcPos = imSize - (i + 1) * (bytesPerScanline + padding);
        int dstPos = i * bytesPerScanline;
        for (int k = 0; k < bytesPerScanline; k++) {
          bdata[dstPos + k] = values[srcPos + k];
        }
      }
    } else {
      for (int i = 0; i < bmp.height; i++) {
        int srcPos = i * (bytesPerScanline + padding);
        int dstPos = i * bytesPerScanline;
        for (int k = 0; k < bytesPerScanline; k++) {
          bdata[dstPos + k] = values[srcPos + k];
        }
      }
    }
    _indexedModel(bdata, 1, paletteEntries, bmp);
  }

  static void _read4Bit(int paletteEntries, BmpParameters bmp) {
    int bytesPerScanline = (bmp.width / 2.0).ceil();
    int padding = 0;
    int remainder = bytesPerScanline % 4;
    if (remainder != 0) {
      padding = 4 - remainder;
    }
    int imSize = (bytesPerScanline + padding) * bmp.height;
    Uint8List values = Uint8List(imSize);
    bmp.inputStream!.readFully(values);

    Uint8List bdata = Uint8List((bmp.width + 1) ~/ 2 * bmp.height);

    if (bmp.isBottomUp) {
      for (int i = 0; i < bmp.height; i++) {
        int srcPos = imSize - (i + 1) * (bytesPerScanline + padding);
        int dstPos = i * bytesPerScanline;
        for (int k = 0; k < bytesPerScanline; k++) {
          bdata[dstPos + k] = values[srcPos + k];
        }
      }
    } else {
      for (int i = 0; i < bmp.height; i++) {
        int srcPos = i * (bytesPerScanline + padding);
        int dstPos = i * bytesPerScanline;
        for (int k = 0; k < bytesPerScanline; k++) {
          bdata[dstPos + k] = values[srcPos + k];
        }
      }
    }
    _indexedModel(bdata, 4, paletteEntries, bmp);
  }

  static void _read8Bit(int paletteEntries, BmpParameters bmp) {
    int padding = 0;
    int bitsPerScanline = bmp.width * 8;
    if (bitsPerScanline % 32 != 0) {
      padding = (bitsPerScanline / 32 + 1).floor() * 32 - bitsPerScanline;
      padding = (padding / 8.0).ceil();
    }
    int imSize = (bmp.width + padding) * bmp.height;
    Uint8List values = Uint8List(imSize);
    bmp.inputStream!.readFully(values);

    Uint8List bdata = Uint8List(bmp.width * bmp.height);

    if (bmp.isBottomUp) {
      for (int i = 0; i < bmp.height; i++) {
        int srcPos = imSize - (i + 1) * (bmp.width + padding);
        int dstPos = i * bmp.width;
        for (int k = 0; k < bmp.width; k++) {
          bdata[dstPos + k] = values[srcPos + k];
        }
      }
    } else {
      for (int i = 0; i < bmp.height; i++) {
        int srcPos = i * (bmp.width + padding);
        int dstPos = i * bmp.width;
        for (int k = 0; k < bmp.width; k++) {
          bdata[dstPos + k] = values[srcPos + k];
        }
      }
    }
    _indexedModel(bdata, 8, paletteEntries, bmp);
  }

  static void _read24Bit(Uint8List bdata, BmpParameters bmp) {
    int padding = 0;
    int bitsPerScanline = bmp.width * 24;
    if (bitsPerScanline % 32 != 0) {
      padding = (bitsPerScanline / 32 + 1).floor() * 32 - bitsPerScanline;
      padding = (padding / 8.0).ceil();
    }
    int imSize = ((bmp.width * 3 + 3) ~/ 4) * 4 * bmp.height;
    Uint8List values = Uint8List(imSize);
    // readFully usually reads all.
    // If we need partial reads handle loop. But readFully handles it.
    // C# code breaks if r < 0, but readFully throws or handles EOF.
    bmp.inputStream!.readFully(values);

    int l = 0;
    int count;
    if (bmp.isBottomUp) {
      int max = bmp.width * bmp.height * 3 - 1;
      count = -padding;
      for (int i = 0; i < bmp.height; i++) {
        l = max - (i + 1) * bmp.width * 3 + 1;
        count += padding;
        for (int j = 0; j < bmp.width; j++) {
          bdata[l + 2] = values[count++];
          bdata[l + 1] = values[count++];
          bdata[l] = values[count++];
          l += 3;
        }
      }
    } else {
      count = -padding;
      for (int i = 0; i < bmp.height; i++) {
        count += padding;
        for (int j = 0; j < bmp.width; j++) {
          bdata[l + 2] = values[count++];
          bdata[l + 1] = values[count++];
          bdata[l] = values[count++];
          l += 3;
        }
      }
    }
  }

  static void _read1632Bit(bool is32, BmpParameters bmp) {
    int redMask = _findMask(bmp.redMask);
    int redShift = _findShift(bmp.redMask);
    int redFactor = redMask + 1;
    int greenMask = _findMask(bmp.greenMask);
    int greenShift = _findShift(bmp.greenMask);
    int greenFactor = greenMask + 1;
    int blueMask = _findMask(bmp.blueMask);
    int blueShift = _findShift(bmp.blueMask);
    int blueFactor = blueMask + 1;

    Uint8List bdata = Uint8List(bmp.width * bmp.height * 3);
    int padding = 0;
    if (!is32) {
      int bitsPerScanline = bmp.width * 16;
      if (bitsPerScanline % 32 != 0) {
        padding = (bitsPerScanline / 32 + 1).floor() * 32 - bitsPerScanline;
        padding = (padding / 8.0).ceil();
      }
    }

    int imSize = bmp.imageSize;
    if (imSize == 0) {
      imSize = (bmp.bitmapFileSize - bmp.bitmapOffset);
    }

    int l = 0;
    int v;
    if (bmp.isBottomUp) {
      for (int i = bmp.height - 1; i >= 0; --i) {
        l = bmp.width * 3 * i;
        for (int j = 0; j < bmp.width; j++) {
          if (is32) {
            v = bmp.inputStream!
                .readIntLE(); // DWord is usually unsigned but readIntLE is signed.
            // Mask logic works nicely with signed/unsigned if we treat as uint.
            // Dart int is 64-bit so reading 32-bit int fits.
          } else {
            v = bmp.inputStream!.readUnsignedShortLE();
          }

          int r = (((v >> redShift) & redMask) * 256) ~/ redFactor;
          int g = (((v >> greenShift) & greenMask) * 256) ~/ greenFactor;
          int b = (((v >> blueShift) & blueMask) * 256) ~/ blueFactor;

          bdata[l++] = r;
          bdata[l++] = g;
          bdata[l++] = b;
        }
        for (int m = 0; m < padding; m++) {
          bmp.inputStream!.read();
        }
      }
    } else {
      for (int i = 0; i < bmp.height; i++) {
        for (int j = 0; j < bmp.width; j++) {
          if (is32) {
            v = bmp.inputStream!.readIntLE();
          } else {
            v = bmp.inputStream!.readUnsignedShortLE();
          }
          int r = (((v >> redShift) & redMask) * 256) ~/ redFactor;
          int g = (((v >> greenShift) & greenMask) * 256) ~/ greenFactor;
          int b = (((v >> blueShift) & blueMask) * 256) ~/ blueFactor;
          bdata[l++] = r;
          bdata[l++] = g;
          bdata[l++] = b;
        }
        for (int m = 0; m < padding; m++) {
          bmp.inputStream!.read();
        }
      }
    }
    RawImageHelper.updateRawImageParameters(
        bmp.image, bmp.width, bmp.height, 3, 8, bdata);
  }

  static void _readRle8(BmpParameters bmp) {
    int imSize = bmp.imageSize;
    if (imSize == 0) {
      imSize = (bmp.bitmapFileSize - bmp.bitmapOffset);
    }
    Uint8List values = Uint8List(imSize);
    bmp.inputStream!.readFully(values);
    Uint8List val = _decodeRle(true, values, bmp);

    imSize = bmp.width * bmp.height;
    if (bmp.isBottomUp) {
      Uint8List temp = Uint8List(val.length);
      int bytesPerScanline = bmp.width;
      for (int i = 0; i < bmp.height; i++) {
        int srcPos = imSize - (i + 1) * bytesPerScanline;
        int dstPos = i * bytesPerScanline;
        for (int k = 0; k < bytesPerScanline; k++) {
          temp[dstPos + k] = val[srcPos + k];
        }
      }
      val = temp;
    }
    _indexedModel(val, 8, 4, bmp);
  }

  static void _readRle4(BmpParameters bmp) {
    int imSize = bmp.imageSize;
    if (imSize == 0) {
      imSize = (bmp.bitmapFileSize - bmp.bitmapOffset);
    }
    Uint8List values = Uint8List(imSize);
    bmp.inputStream!.readFully(values);
    Uint8List val = _decodeRle(false, values, bmp);

    if (bmp.isBottomUp) {
      Uint8List inverted = val;
      val = Uint8List(bmp.width * bmp.height);
      int l = 0;
      int index;
      int lineEnd;
      for (int i = bmp.height - 1; i >= 0; i--) {
        index = i * bmp.width;
        lineEnd = l + bmp.width;
        while (l != lineEnd) {
          val[l++] = inverted[index++];
        }
      }
    }

    int stride = (bmp.width + 1) ~/ 2;
    Uint8List bdata = Uint8List(stride * bmp.height);
    int ptr = 0;
    int sh = 0;
    for (int h = 0; h < bmp.height; ++h) {
      for (int w = 0; w < bmp.width; ++w) {
        if ((w & 1) == 0) {
          bdata[sh + w ~/ 2] = (val[ptr++] << 4);
        } else {
          bdata[sh + w ~/ 2] = bdata[sh + w ~/ 2] | (val[ptr++] & 0x0f);
        }
      }
      sh += stride;
    }
    _indexedModel(bdata, 4, 4, bmp);
  }

  static Uint8List _decodeRle(bool is8, Uint8List values, BmpParameters bmp) {
    Uint8List val = Uint8List(bmp.width * bmp.height);
    try {
      int ptr = 0;
      int x = 0;
      int q = 0;
      for (int y = 0; y < bmp.height && ptr < values.length;) {
        int count = values[ptr++] & 0xff;
        if (count != 0) {
          // encoded mode
          int bt = values[ptr++] & 0xff;
          if (is8) {
            for (int i = count; i != 0; --i) {
              val[q++] = bt;
            }
          } else {
            for (int i = 0; i < count; ++i) {
              val[q++] = ((i & 1) == 1 ? bt & 0x0f : (bt >> 4) & 0x0f);
            }
          }
          x += count;
        } else {
          // escape mode
          count = values[ptr++] & 0xff;
          if (count == 1) {
            break;
          }
          switch (count) {
            case 0:
              x = 0;
              ++y;
              q = y * bmp.width;
              break;
            case 2:
              // delta mode
              x += values[ptr++] & 0xff;
              y += values[ptr++] & 0xff;
              q = y * bmp.width + x;
              break;
            default:
              // absolute mode
              if (is8) {
                for (int i = count; i != 0; --i) {
                  val[q++] = values[ptr++] & 0xff;
                }
              } else {
                int bt = 0;
                for (int i = 0; i < count; ++i) {
                  if ((i & 1) == 0) {
                    bt = values[ptr++] & 0xff;
                  }
                  val[q++] = ((i & 1) == 1 ? bt & 0x0f : (bt >> 4) & 0x0f);
                }
              }
              x += count;
              // read pad byte
              if (is8) {
                if ((count & 1) == 1) {
                  ++ptr;
                }
              } else {
                if ((count & 3) == 1 || (count & 3) == 2) {
                  ++ptr;
                }
              }
              break;
          }
        }
      }
    } catch (e) {
      // Ignore
    }
    return val;
  }

  static void _indexedModel(
      Uint8List bdata, int bpc, int paletteEntries, BmpParameters bmp) {
    RawImageHelper.updateRawImageParameters(
        bmp.image, bmp.width, bmp.height, 1, bpc, bdata);

    List<Object> colorSpace = List.filled(4, "");
    colorSpace[0] = "/Indexed";
    colorSpace[1] = "/DeviceRGB";
    Uint8List np = _getPalette(paletteEntries, bmp);
    int len = np.length;
    colorSpace[2] = (len ~/ 3) - 1;
    colorSpace[3] = PdfEncodings.convertToString(np, null);

    bmp.additional ??= {};
    bmp.additional!["ColorSpace"] = colorSpace;
  }

  static Uint8List _getPalette(int group, BmpParameters bmp) {
    if (bmp.palette == null) {
      return Uint8List(0);
    }
    Uint8List np = Uint8List(bmp.palette!.length ~/ group * 3);
    int e = bmp.palette!.length ~/ group;
    for (int k = 0; k < e; ++k) {
      int src = k * group;
      int dest = k * 3;
      np[dest + 2] = bmp.palette![src++];
      np[dest + 1] = bmp.palette![src++];
      np[dest] = bmp.palette![src];
    }
    return np;
  }

  static int _findMask(int mask) {
    int k = 0;
    for (; k < 32; ++k) {
      if ((mask & 1) == 1) {
        break;
      }
      mask = mask >> 1; // Unsigned shift not strictly needed if positive
    }
    return mask;
  }

  static int _findShift(int mask) {
    int k = 0;
    for (; k < 32; ++k) {
      if ((mask & 1) == 1) {
        break;
      }
      mask = mask >> 1;
    }
    return k;
  }
}

class BmpParameters {
  BmpImageData image;
  int width = 0;
  int height = 0;
  Map<String, Object>? additional;
  RandomAccessFileOrArray? inputStream;
  int bitmapFileSize = 0;
  int bitmapOffset = 0;
  int compression = 0;
  int imageSize = 0;
  Uint8List? palette;
  int imageType = 0;
  int numBands = 0;
  bool isBottomUp = false;
  int bitsPerPixel = 0;
  int redMask = 0;
  int greenMask = 0;
  int blueMask = 0;
  int alphaMask = 0;
  Map<String, Object?> properties = {};

  int xPelsPerMeter = 0;
  int yPelsPerMeter = 0;

  BmpParameters(this.image);
}
