import 'dart:typed_data';

import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';
import 'package:dpdf/src/io/image/bmp_image_data.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/io/image/raw_image_helper.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'package:dpdf/src/io/font/pdf_encodings.dart';

import 'package:dpdf/src/layout/properties/image_type.dart';

class CraftBmpImageHelper {
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
  static void processImage(CraftImageData image) {
    if (image.getOriginalType() != CraftImageType.BMP) {
      throw ArgumentError("BMP image expected");
    }

    try {
      if (image.getData() == null) {
        // In Dart we typically expect data to be present if it wasn't loaded via URL in a way that deferred loading.
        // If image.url is set and data is null, we might need a way to load it, but usually this is handled before calling helper.
        throw IoException("Image data is null");
      }

      final bmp = BmpParameters(image as CraftBmpImageData);
      // Using RandomAccessFileOrArray instead of Stream for easier seeking and LE reading
      final stream = CraftRandomAccessFileOrArray(image.getData()!);

      image.imageSize = image.getData()!.length;

      _process(bmp, stream);

      if (_getImage(bmp)) {
        image.setWidth(bmp.width.toDouble());
        image.setHeight(bmp.height.toDouble());
        final dpiX = (bmp.xPelsPerMeter * 0.0254 + 0.5).toInt();
        final dpiY = (bmp.yPelsPerMeter * 0.0254 + 0.5).toInt();
        image.setDpi(dpiX, dpiY);
      }

      CraftRawImageHelper.updateImageAttributes(bmp.image, bmp.additional);

      stream.close();
    } catch (e) {
      if (e is IoException) rethrow;
      throw IoException(CraftIoExceptionMessageConstant.bmpImageException, e);
    }
  }

  static void _process(BmpParameters bmp, CraftRandomAccessFileOrArray stream) {
    bmp.inputStream = stream;
    if (!bmp.image.isNoHeader()) {
      // Start File Header
      if (!(stream.readUnsignedByte() == 0x42 &&
          stream.readUnsignedByte() == 0x4D)) {
        // 'B' 'M'
        throw IoException(CraftIoExceptionMessageConstant
            .invalidMagicValueForBmpFileMustBeBm);
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
                CraftIoExceptionMessageConstant.invalidBmpFileCompression);
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
        CraftRawImageHelper.updateRawImageParameters(
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
              CraftIoExceptionMessageConstant.invalidBmpFileCompression);
        }
        return true;
      case version3_8bit:
        if (bmp.compression == biRgb) {
          _read8Bit(4, bmp);
        } else if (bmp.compression == biRle8) {
          _readRle8(bmp);
        } else {
          throw IoException(
              CraftIoExceptionMessageConstant.invalidBmpFileCompression);
        }
        return true;
      case version3_24bit:
        Uint8List bdata = Uint8List(bmp.width * bmp.height * 3);
        _read24Bit(bdata, bmp);
        CraftRawImageHelper.updateRawImageParameters(
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
              CraftIoExceptionMessageConstant.invalidBmpFileCompression);
        }
        return true;
      case version4_8bit:
        if (bmp.compression == biRgb) {
          _read8Bit(4, bmp);
        } else if (bmp.compression == biRle8) {
          _readRle8(bmp);
        } else {
          throw IoException(
              CraftIoExceptionMessageConstant.invalidBmpFileCompression);
        }
        return true;
      case version4_16bit:
        _read1632Bit(false, bmp);
        return true;
      case version4_24bit:
        Uint8List bdata = Uint8List(bmp.width * bmp.height * 3);
        _read24Bit(bdata, bmp);
        CraftRawImageHelper.updateRawImageParameters(
            bmp.image, bmp.width, bmp.height, 3, 8, bdata);
        return true;
      case version4_32bit:
        _read1632Bit(true, bmp);
        return true;
    }
    return false;
  }

  // Read each stored row once into its final visual position. BMP rows occupy
  // a multiple of four bytes; packed sample bytes themselves have no padding.
  static Uint8List _rasterRows(BmpParameters bmp, int sampleBits) {
    final payload = (bmp.width * sampleBits + 7) ~/ 8;
    final storage = ((payload + 3) ~/ 4) * 4;
    final row = Uint8List(storage);
    final raster = Uint8List(payload * bmp.height);
    for (var stored = 0; stored < bmp.height; stored++) {
      bmp.inputStream!.readFully(row);
      final visual = bmp.isBottomUp ? bmp.height - stored - 1 : stored;
      raster.setRange(visual * payload, (visual + 1) * payload, row);
    }
    return raster;
  }

  static void _read1Bit(int paletteEntries, BmpParameters bmp) =>
      _indexedModel(_rasterRows(bmp, 1), 1, paletteEntries, bmp);

  static void _read4Bit(int paletteEntries, BmpParameters bmp) =>
      _indexedModel(_rasterRows(bmp, 4), 4, paletteEntries, bmp);

  static void _read8Bit(int paletteEntries, BmpParameters bmp) =>
      _indexedModel(_rasterRows(bmp, 8), 8, paletteEntries, bmp);

  static void _read24Bit(Uint8List bdata, BmpParameters bmp) {
    final stored = _rasterRows(bmp, 24);
    for (var offset = 0; offset < stored.length; offset += 3) {
      bdata[offset] = stored[offset + 2];
      bdata[offset + 1] = stored[offset + 1];
      bdata[offset + 2] = stored[offset];
    }
  }

  static void _read1632Bit(bool is32, BmpParameters bmp) {
    final bytes = _rasterRows(bmp, is32 ? 32 : 16);
    final samples = ByteData.sublistView(bytes);
    final pixelBytes = is32 ? 4 : 2;
    final rgb = Uint8List(bmp.width * bmp.height * 3);
    final channels = [bmp.redMask, bmp.greenMask, bmp.blueMask];
    final shifts = channels.map(_findShift).toList();
    final masks = channels.map(_findMask).toList();
    for (var pixel = 0; pixel < bmp.width * bmp.height; pixel++) {
      final offset = pixel * pixelBytes;
      final value = is32
          ? samples.getUint32(offset, Endian.little)
          : samples.getUint16(offset, Endian.little);
      for (var channel = 0; channel < 3; channel++) {
        final component = (value >>> shifts[channel]) & masks[channel];
        rgb[pixel * 3 + channel] = component * 256 ~/ (masks[channel] + 1);
      }
    }
    CraftRawImageHelper.updateRawImageParameters(
        bmp.image, bmp.width, bmp.height, 3, 8, rgb);
  }

  static void _readRle8(BmpParameters bmp) {
    int imSize = bmp.imageSize;
    if (imSize == 0) {
      imSize = (bmp.bitmapFileSize - bmp.bitmapOffset);
    }
    Uint8List values = Uint8List(imSize);
    bmp.inputStream!.readFully(values);
    Uint8List val = _decodeRle(true, values, bmp);

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

    final rowBytes = (bmp.width + 1) ~/ 2;
    final bdata = Uint8List(rowBytes * bmp.height);
    for (var packed = 0; packed < bdata.length; packed++) {
      final row = packed ~/ rowBytes;
      final column = (packed % rowBytes) * 2;
      final source = row * bmp.width + column;
      final low = column + 1 < bmp.width ? val[source + 1] : 0;
      bdata[packed] = (val[source] << 4) | (low & 15);
    }
    _indexedModel(bdata, 4, 4, bmp);
  }

  static Uint8List _decodeRle(bool is8, Uint8List values, BmpParameters bmp) {
    final pixels = Uint8List(bmp.width * bmp.height);
    var cursor = 0, column = 0, row = 0;
    int take() {
      if (cursor == values.length) {
        throw IoException('BMP run data is incomplete.');
      }
      return values[cursor++];
    }

    while (cursor < values.length && row < bmp.height) {
      final run = take();
      final command = take();
      if (run == 0 && command < 3) {
        if (command == 1) return pixels;
        if (command == 0) {
          row++;
          column = 0;
        } else {
          column += take();
          row += take();
          if (column > bmp.width || row >= bmp.height) {
            throw IoException('BMP run displacement exceeds the raster.');
          }
        }
        continue;
      }
      final length = run == 0 ? command : run;
      if (column + length > bmp.width) {
        throw IoException('BMP run crosses a scanline boundary.');
      }
      final literalBytes = is8 ? length : (length + 1) ~/ 2;
      final start = cursor;
      if (run == 0 &&
          values.length - cursor < literalBytes + (literalBytes % 2)) {
        throw IoException('BMP literal run or alignment byte is incomplete.');
      }
      for (var sample = 0; sample < length; sample++) {
        final packed =
            run == 0 ? values[start + (is8 ? sample : sample ~/ 2)] : command;
        final index = is8 ? packed : (packed >> (sample.isEven ? 4 : 0)) & 15;
        final targetRow = bmp.isBottomUp ? bmp.height - row - 1 : row;
        pixels[targetRow * bmp.width + column + sample] = index;
      }
      column += length;
      if (run == 0) cursor += literalBytes + (literalBytes % 2);
    }
    return pixels;
  }

  static void _indexedModel(
      Uint8List bdata, int bpc, int paletteEntries, BmpParameters bmp) {
    CraftRawImageHelper.updateRawImageParameters(
        bmp.image, bmp.width, bmp.height, 1, bpc, bdata);

    List<Object> colorSpace = List.filled(4, "");
    colorSpace[0] = "/Indexed";
    colorSpace[1] = "/DeviceRGB";
    Uint8List np = _getPalette(paletteEntries, bmp);
    int len = np.length;
    colorSpace[2] = (len ~/ 3) - 1;
    colorSpace[3] = CraftPdfEncodings.convertToString(np, null);

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
  CraftBmpImageData image;
  int width = 0;
  int height = 0;
  Map<String, Object>? additional;
  CraftRandomAccessFileOrArray? inputStream;
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
