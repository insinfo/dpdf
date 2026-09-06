import 'dart:typed_data';

import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';
import 'package:dpdf/src/io/image/gif_image_data.dart';

import 'package:dpdf/src/io/image/raw_image_data.dart';
import 'package:dpdf/src/io/image/raw_image_helper.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'package:dpdf/src/io/font/pdf_encodings.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';

class GifImageHelper {
  static const int _maxStackSize = 4096;

  /// Reads image source and fills GifImage object with parameters (frames, width, height)
  static void processImage(GifImageData image, [int lastFrameNumber = -1]) {
    final gif = GifParameters(image);
    try {
      if (image.getData() == null) {
        // Assuming data is loaded or available
        throw IoException("Image data is null");
      }
      final stream = RandomAccessFileOrArray(image.getData()!);
      _process(stream, gif, lastFrameNumber);
      stream.close();
    } catch (e) {
      if (e is IoException) rethrow;
      throw IoException(IoExceptionMessageConstant.gifImageException, e);
    }
  }

  static void _process(
      RandomAccessFileOrArray stream, GifParameters gif, int lastFrameNumber) {
    gif.input = stream;
    _readHeader(gif);
    _readContents(gif, lastFrameNumber);
    if (gif.currentFrame <= lastFrameNumber) {
      throw IoException(IoExceptionMessageConstant.cannotFindFrame);
    }
  }

  static void _readHeader(GifParameters gif) {
    StringBuffer id = StringBuffer("");
    for (int i = 0; i < 6; i++) {
      id.writeCharCode(gif.input!.read());
    }
    if (!id.toString().startsWith("GIF8")) {
      throw IoException(IoExceptionMessageConstant.gifSignatureNotFound);
    }
    _readLSD(gif);
    if (gif.gctFlag) {
      gif.mGlobalTable = _readColorTable(gif.mGbpc, gif);
    }
  }

  static void _readLSD(GifParameters gif) {
    // logical screen size
    gif.image.setLogicalWidth(_readShort(gif).toDouble());
    gif.image.setLogicalHeight(_readShort(gif).toDouble());
    // packed fields
    int packed = gif.input!.read();
    // 1   : global color table flag
    gif.gctFlag = (packed & 0x80) != 0;
    gif.mGbpc = (packed & 7) + 1;
    // background color index
    gif.bgIndex = gif.input!.read();
    // pixel aspect ratio
    gif.pixelAspect = gif.input!.read();
  }

  static int _readShort(GifParameters gif) {
    // read 16-bit value, LSB first
    return gif.input!.read() | (gif.input!.read() << 8);
  }

  static int _readBlock(GifParameters gif) {
    gif.blockSize = gif.input!.read();
    if (gif.blockSize <= 0) {
      return gif.blockSize = 0;
    }
    // Read blockSize bytes into block buffer
    int count = gif.input!.readBufferInto(gif.block, 0, gif.blockSize);
    gif.blockSize = count;
    return count;
    // Note: C# uses JRead which handles EOF differently?
    // here we assume it reads what's available.
  }

  static Uint8List _readColorTable(int bpc, GifParameters gif) {
    int ncolors = 1 << bpc;
    int nbytes = 3 * ncolors;
    bpc = _newBpc(bpc);
    Uint8List table = Uint8List((1 << bpc) * 3);
    // StreamUtil.readFully equivalent.
    // RandomAccessFileOrArray has readFullyInto
    gif.input!.readFullyInto(table, 0, nbytes);
    return table;
  }

  static int _newBpc(int bpc) {
    switch (bpc) {
      case 1:
      case 2:
      case 4:
        break;
      case 3:
        return 4;
      default:
        return 8;
    }
    return bpc;
  }

  static void _readContents(GifParameters gif, int lastFrameNumber) {
    bool done = false;
    gif.currentFrame = 0;
    while (!done) {
      int code = gif.input!.read();
      switch (code) {
        case 0x2C:
          // image separator
          _readFrame(gif);
          if (gif.currentFrame == lastFrameNumber) {
            done = true;
          }
          gif.currentFrame++;
          break;

        case 0x21:
          // extension
          code = gif.input!.read();
          switch (code) {
            case 0xf9:
              // graphics control extension
              _readGraphicControlExt(gif);
              break;

            case 0xff:
              // application extension
              _readBlock(gif);
              _skip(gif);
              break;

            default:
              // uninteresting extension
              _skip(gif);
              break;
          }
          break;

        default:
          done = true;
          break;
      }
    }
  }

  static void _readFrame(GifParameters gif) {
    gif.ix = _readShort(gif);
    gif.iy = _readShort(gif);
    gif.iw = _readShort(gif);
    gif.ih = _readShort(gif);
    int packed = gif.input!.read();

    gif.lctFlag = (packed & 0x80) != 0;
    gif.interlace = (packed & 0x40) != 0;

    gif.lctSize = 2 << (packed & 7);
    gif.mBpc = _newBpc(gif.mGbpc);

    if (gif.lctFlag) {
      gif.mCurrTable = _readColorTable((packed & 7) + 1, gif);
      gif.mBpc = _newBpc((packed & 7) + 1);
    } else {
      gif.mCurrTable = gif.mGlobalTable;
    }

    if (gif.transparency &&
        gif.mCurrTable != null &&
        gif.transIndex >= gif.mCurrTable!.length ~/ 3) {
      gif.transparency = false;
    }

    if (gif.transparency && gif.mBpc == 1 && gif.mCurrTable != null) {
      Uint8List tp = Uint8List(12);
      // Array.Copy
      for (int k = 0; k < 6; k++) {
        if (k < gif.mCurrTable!.length) tp[k] = gif.mCurrTable![k];
      }
      gif.mCurrTable = tp;
      gif.mBpc = 2;
    }

    bool skipZero = _decodeImageData(gif);
    if (!skipZero) {
      _skip(gif);
    }

    try {
      final colorspace = List<Object?>.filled(4, null);
      colorspace[0] = "/Indexed";
      colorspace[1] = "/DeviceRGB";
      int len = gif.mCurrTable!.length;
      colorspace[2] = (len ~/ 3) - 1;
      colorspace[3] = PdfEncodings.convertToString(gif.mCurrTable!, null);

      Map<String, Object> ad = {};
      ad["ColorSpace"] = colorspace;

      RawImageData img = RawImageData.fromBytes(gif.mOut!, ImageType.GIF);
      RawImageHelper.updateRawImageParameters(
          img, gif.iw, gif.ih, 1, gif.mBpc, gif.mOut!);
      RawImageHelper.updateImageAttributes(img, ad);
      gif.image.addFrame(img);

      if (gif.transparency) {
        img.setTransparency([gif.transIndex, gif.transIndex]);
      }
    } catch (e) {
      if (e is IoException) rethrow;
      throw IoException(IoExceptionMessageConstant.gifImageException, e);
    }
  }

  static bool _decodeImageData(GifParameters gif) {
    int nullCode = -1;
    int npix = gif.iw * gif.ih;
    int available;
    int clear;
    int codeMask;
    int codeSize;
    int endOfInformation;
    int inCode;
    int oldCode;
    int bits;
    int code;
    int count;
    int i;
    int datum;
    int dataSize;
    int first;
    int top;
    int bi;
    bool skipZero = false;

    if (gif.prefix == null) {
      gif.prefix = Int16List(_maxStackSize);
    }
    if (gif.suffix == null) {
      gif.suffix = Uint8List(_maxStackSize);
    }
    if (gif.pixelStack == null) {
      gif.pixelStack = Uint8List(_maxStackSize + 1);
    }

    gif.mLineStride = (gif.iw * gif.mBpc + 7) ~/ 8;
    gif.mOut = Uint8List(gif.mLineStride * gif.ih);

    int pass = 1;
    int inc = gif.interlace ? 8 : 1;
    int line = 0;
    int xpos = 0;

    dataSize = gif.input!.read();
    clear = 1 << dataSize;
    endOfInformation = clear + 1;
    available = clear + 2;
    oldCode = nullCode;
    codeSize = dataSize + 1;
    codeMask = (1 << codeSize) - 1;

    for (code = 0; code < clear; code++) {
      gif.prefix![code] = 0;
      gif.suffix![code] = code;
    }

    datum = bits = count = first = top = bi = 0;
    for (i = 0; i < npix;) {
      if (top == 0) {
        if (bits < codeSize) {
          if (count == 0) {
            count = _readBlock(gif);
            if (count <= 0) {
              skipZero = true;
              break;
            }
            bi = 0;
          }
          datum += (gif.block[bi] & 0xff) << bits;
          bits += 8;
          bi++;
          count--;
          continue;
        }
        code = datum & codeMask;
        datum >>= codeSize;
        bits -= codeSize;

        if (code > available || code == endOfInformation) {
          break;
        }
        if (code == clear) {
          codeSize = dataSize + 1;
          codeMask = (1 << codeSize) - 1;
          available = clear + 2;
          oldCode = nullCode;
          continue;
        }
        if (oldCode == nullCode) {
          gif.pixelStack![top++] = gif.suffix![code];
          oldCode = code;
          first = code;
          continue;
        }
        inCode = code;
        if (code == available) {
          gif.pixelStack![top++] = first;
          code = oldCode;
        }
        while (code > clear) {
          gif.pixelStack![top++] = gif.suffix![code];
          code = gif.prefix![code];
        }
        first = gif.suffix![code] & 0xff;

        if (available >= _maxStackSize) {
          break;
        }
        gif.pixelStack![top++] = first;
        gif.prefix![available] = oldCode;
        gif.suffix![available] = first;
        available++;

        if ((available & codeMask) == 0 && available < _maxStackSize) {
          codeSize++;
          codeMask += available;
        }
        oldCode = inCode;
      }
      top--;
      i++;
      _setPixel(xpos, line, gif.pixelStack![top], gif);
      xpos++;
      if (xpos >= gif.iw) {
        xpos = 0;
        line += inc;
        if (line >= gif.ih) {
          if (gif.interlace) {
            do {
              pass++;
              switch (pass) {
                case 2:
                  line = 4;
                  break;
                case 3:
                  line = 2;
                  inc = 4;
                  break;
                case 4:
                  line = 1;
                  inc = 2;
                  break;
                default:
                  line = gif.ih - 1;
                  inc = 0;
              }
            } while (line >= gif.ih);
          } else {
            line = gif.ih - 1;
            inc = 0;
          }
        }
      }
    }
    return skipZero;
  }

  static void _setPixel(int x, int y, int v, GifParameters gif) {
    if (gif.mBpc == 8) {
      int pos = x + gif.iw * y;
      if (pos < gif.mOut!.length) {
        gif.mOut![pos] = v;
      }
    } else {
      int pos = gif.mLineStride * y + x ~/ (8 ~/ gif.mBpc);
      int shift = 8 - gif.mBpc * (x % (8 ~/ gif.mBpc)) - gif.mBpc;
      int vout = v << shift;
      if (pos < gif.mOut!.length) {
        gif.mOut![pos] = gif.mOut![pos] | vout;
      }
    }
  }

  static void _readGraphicControlExt(GifParameters gif) {
    gif.input!.read(); // block size
    int packed = gif.input!.read();
    gif.dispose = (packed & 0x1c) >> 2;
    if (gif.dispose == 0) {
      gif.dispose = 1;
    }
    gif.transparency = (packed & 1) != 0;
    gif.delay = _readShort(gif) * 10;
    gif.transIndex = gif.input!.read();
    gif.input!.read(); // terminator
  }

  static void _skip(GifParameters gif) {
    do {
      _readBlock(gif);
    } while (gif.blockSize > 0);
  }
}

class GifParameters {
  GifImageData image;
  RandomAccessFileOrArray? input;
  bool gctFlag = false;
  int bgIndex = 0;
  int bgColor = 0;
  int pixelAspect = 0;
  bool lctFlag = false;
  bool interlace = false;
  int lctSize = 0;
  int ix = 0;
  int iy = 0;
  int iw = 0;
  int ih = 0;
  final Uint8List block = Uint8List(256);
  int blockSize = 0;
  int dispose = 0;
  bool transparency = false;
  int delay = 0;
  int transIndex = 0;
  Int16List? prefix;
  Uint8List? suffix;
  Uint8List? pixelStack;
  Uint8List? pixels; // unused?
  Uint8List? mOut;
  int mBpc = 0;
  int mGbpc = 0;
  Uint8List? mGlobalTable;
  Uint8List? mLocalTable; // unused?
  Uint8List? mCurrTable;
  int mLineStride = 0;
  int currentFrame = 0;

  GifParameters(this.image);
}
