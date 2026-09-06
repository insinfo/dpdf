import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dpdf/src/io/codec/ccitt_g4_encoder.dart';
import 'package:dpdf/src/io/codec/tiff_constants.dart';
import 'package:dpdf/src/io/codec/tiff_directory.dart';
import 'package:dpdf/src/io/codec/tiff_fax_decoder.dart';
import 'package:dpdf/src/io/codec/tiff_field.dart';
import 'package:dpdf/src/io/codec/tiff_lzw_decoder.dart';
import 'package:dpdf/src/io/colors/icc_profile.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';
import 'package:dpdf/src/io/font/pdf_encodings.dart';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/io/image/image_data_factory.dart';
import 'package:dpdf/src/io/image/jpeg_image_helper.dart';
import 'package:dpdf/src/io/image/raw_image_data.dart';
import 'package:dpdf/src/io/image/raw_image_helper.dart';
import 'package:dpdf/src/io/image/tiff_image_data.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';

class _TiffParameters {
  TiffImageData image;
  bool jpegProcessing = false;
  Map<String, Object>? additional;

  _TiffParameters(this.image);
}

class TiffImageHelper {
  static void processImage(ImageData image) {
    if (image.getOriginalType() != ImageType.TIFF) {
      throw ArgumentError("TIFF image expected");
    }
    try {
      if (image.getData() == null) {
        // Handle loading data if not present
      }
      final raf = RandomAccessFileOrArray(image.getData()!);
      final tiff = _TiffParameters(image as TiffImageData);
      processTiffImage(raf, tiff);
      raf.close();
      if (!tiff.jpegProcessing) {
        RawImageHelper.updateImageAttributes(tiff.image, tiff.additional);
      }
    } catch (e) {
      throw IoException(IoExceptionMessageConstant.tiffImageException, e);
    }
  }

  static void processTiffImage(
      RandomAccessFileOrArray s, _TiffParameters tiff) {
    bool recoverFromImageError = tiff.image.isRecoverFromImageError();
    int page = tiff.image.getPage();
    bool direct = tiff.image.isDirect();
    if (page < 1) {
      throw IoException(IoExceptionMessageConstant.pageNumberMustBeGtEq1);
    }
    try {
      TiffDirectory dir = TiffDirectory(s, directory: page - 1);
      if (dir.isTagPresent(TiffConstants.tifftagTilewidth)) {
        throw IoException(IoExceptionMessageConstant.tilesAreNotSupported);
      }
      int compression = TiffConstants.compressionNone;
      if (dir.isTagPresent(TiffConstants.tifftagCompression)) {
        compression =
            dir.getFieldAsLong(TiffConstants.tifftagCompression).toInt();
      }
      switch (compression) {
        case TiffConstants.compressionCcittrlew:
        case TiffConstants.compressionCcittrle:
        case TiffConstants.compressionCcittfax3:
        case TiffConstants.compressionCcittfax4:
          break;
        default:
          processTiffImageColor(dir, s, tiff);
          return;
      }

      double rotation = 0;
      if (dir.isTagPresent(TiffConstants.tifftagOrientation)) {
        int rot = dir.getFieldAsLong(TiffConstants.tifftagOrientation).toInt();
        if (rot == TiffConstants.orientationTopleft) {
          // Standard, do nothing
        }
        if (rot == 3 || rot == 4) {
          rotation = math.pi;
        } else if (rot == 5 || rot == 8) {
          rotation = math.pi / 2.0;
        } else if (rot == 6 || rot == 7) {
          rotation = -(math.pi / 2.0);
        }
      }

      int tiffT4Options = 0;
      int tiffT6Options = 0;
      int fillOrder = 1;
      int h = dir.getFieldAsLong(TiffConstants.tifftagImagelength).toInt();
      int w = dir.getFieldAsLong(TiffConstants.tifftagImagewidth).toInt();
      double xyRatio = 0;
      int resolutionUnit = TiffConstants.resunitInch;
      if (dir.isTagPresent(TiffConstants.tifftagResolutionunit)) {
        resolutionUnit =
            dir.getFieldAsLong(TiffConstants.tifftagResolutionunit).toInt();
      }
      int dpiX = _getDpi(
          dir.getField(TiffConstants.tifftagXresolution), resolutionUnit);
      int dpiY = _getDpi(
          dir.getField(TiffConstants.tifftagYresolution), resolutionUnit);

      if (resolutionUnit == TiffConstants.resunitNone) {
        if (dpiY != 0) {
          xyRatio = dpiX.toDouble() / dpiY.toDouble();
        }
        dpiX = 0;
        dpiY = 0;
      }

      int rowsStrip = h;
      if (dir.isTagPresent(TiffConstants.tifftagRowsperstrip)) {
        rowsStrip =
            dir.getFieldAsLong(TiffConstants.tifftagRowsperstrip).toInt();
      }
      if (rowsStrip <= 0 || rowsStrip > h) {
        rowsStrip = h;
      }

      List<int>? offset =
          _getArrayLongShort(dir, TiffConstants.tifftagStripoffsets);
      List<int>? size =
          _getArrayLongShort(dir, TiffConstants.tifftagStripbytecounts);

      if ((size == null ||
              (size.length == 1 &&
                  (size[0] == 0 || size[0] + offset![0] > s.length()))) &&
          h == rowsStrip) {
        size = [s.length() - offset![0]];
      } else if (offset == null) {
        throw IoException("TIFF strip offsets missing");
      }

      TiffField? fillOrderField = dir.getField(TiffConstants.tifftagFillorder);
      if (fillOrderField != null) {
        fillOrder = fillOrderField.getAsInt(0);
      }
      // bool reverse = (fillOrder == TiffConstants.fillorderLsb2msb);

      int parameters = 0;
      if (dir.isTagPresent(TiffConstants.tifftagPhotometric)) {
        int photo =
            dir.getFieldAsLong(TiffConstants.tifftagPhotometric).toInt();
        if (photo == TiffConstants.photometricMinisblack) {
          parameters |= RawImageData.ccittBlackis1;
        }
      }

      int imagecomp = 0;
      switch (compression) {
        case TiffConstants.compressionCcittrlew:
        case TiffConstants.compressionCcittrle:
          imagecomp = RawImageData.ccittg31d;
          parameters |=
              RawImageData.ccittEncodedbytealign | RawImageData.ccittEndofblock;
          break;
        case TiffConstants.compressionCcittfax3:
          imagecomp = RawImageData.ccittg31d;
          parameters |=
              RawImageData.ccittEndofline | RawImageData.ccittEndofblock;
          TiffField? t4OptionsField =
              dir.getField(TiffConstants.tifftagGroup3options);
          if (t4OptionsField != null) {
            tiffT4Options = t4OptionsField.getAsLong(0).toInt();
            if ((tiffT4Options & TiffConstants.group3opt2dencoding) != 0) {
              imagecomp = RawImageData.ccittg32d;
            }
            if ((tiffT4Options & TiffConstants.group3optFillbits) != 0) {
              parameters |= RawImageData.ccittEncodedbytealign;
            }
          }
          break;
        case TiffConstants.compressionCcittfax4:
          imagecomp = RawImageData.ccittg4;
          TiffField? t6OptionsField =
              dir.getField(TiffConstants.tifftagGroup4options);
          if (t6OptionsField != null) {
            tiffT6Options = t6OptionsField.getAsLong(0).toInt();
          }
          break;
      }

      if (direct && rowsStrip == h) {
        Uint8List im = Uint8List(size![0]);
        s.seek(offset[0]);
        s.readFully(im);
        RawImageHelper.updateRawImageParameters(
            tiff.image, w, h, 1, 1, im, null);
        RawImageHelper.updateRawImageParametersCCITT(
            tiff.image, w, h, false, imagecomp, parameters, im, null);
        tiff.image.setInverted(true);
      } else {
        int rowsLeft = h;
        var g4 = CCITTG4Encoder(w);

        for (int k = 0; k < offset.length; ++k) {
          Uint8List im = Uint8List(size![k]);
          s.seek(offset[k]);
          s.readFully(im);
          int height = math.min(rowsStrip, rowsLeft);
          TIFFFaxDecoder decoder = TIFFFaxDecoder(fillOrder, w, height);
          decoder.setRecoverFromImageError(recoverFromImageError);
          Uint8List outBuf = Uint8List(((w + 7) ~/ 8) * height);

          switch (compression) {
            case TiffConstants.compressionCcittrlew:
            case TiffConstants.compressionCcittrle:
              decoder.decode1D(outBuf, im, 0, height);
              g4.fax4EncodeHeight(outBuf, height);
              break;
            case TiffConstants.compressionCcittfax3:
              try {
                decoder.decode2D(outBuf, im, 0, height, tiffT4Options);
              } catch (e) {
                tiffT4Options ^= TiffConstants.group3optFillbits;
                try {
                  decoder.decode2D(outBuf, im, 0, height, tiffT4Options);
                } catch (e2) {
                  if (!recoverFromImageError) rethrow;
                  if (rowsStrip == 1) rethrow;
                  im = Uint8List(size[0]);
                  s.seek(offset[0]);
                  s.readFully(im);
                  RawImageHelper.updateRawImageParametersCCITT(
                      tiff.image, w, h, false, imagecomp, parameters, im, null);
                  tiff.image.setInverted(true);
                  tiff.image.setDpi(dpiX, dpiY);
                  tiff.image.setXYRatio(xyRatio);
                  if (rotation != 0) tiff.image.setRotation(rotation);
                  return;
                }
              }
              g4.fax4EncodeHeight(outBuf, height);
              break;
            case TiffConstants.compressionCcittfax4:
              try {
                decoder.decodeT6(outBuf, im, 0, height, tiffT6Options);
              } catch (e) {
                if (!recoverFromImageError) rethrow;
              }
              g4.fax4EncodeHeight(outBuf, height);
              break;
          }
          rowsLeft -= rowsStrip;
        }
        Uint8List g4pic = g4.close();
        RawImageHelper.updateRawImageParametersCCITT(
            tiff.image,
            w,
            h,
            false,
            RawImageData.ccittg4,
            parameters & RawImageData.ccittBlackis1,
            g4pic,
            null);
      }

      tiff.image.setDpi(dpiX, dpiY);
      if (dir.isTagPresent(TiffConstants.tifftagIccprofile)) {
        try {
          TiffField fd = dir.getField(TiffConstants.tifftagIccprofile)!;
          IccProfile iccProf = IccProfile.getInstance(fd.getAsBytes());
          if (iccProf.getNumComponents() == 1) {
            tiff.image.setProfile(iccProf);
          }
        } catch (e) {
          // Ignore
        }
      }
      if (rotation != 0) {
        tiff.image.setRotation(rotation);
      }
    } catch (e) {
      throw IoException(IoExceptionMessageConstant.cannotReadTiffImage, e);
    }
  }

  static void processTiffImageColor(
      TiffDirectory dir, RandomAccessFileOrArray s, _TiffParameters tiff) {
    try {
      int compression = TiffConstants.compressionNone;
      if (dir.isTagPresent(TiffConstants.tifftagCompression)) {
        compression =
            dir.getFieldAsLong(TiffConstants.tifftagCompression).toInt();
      }
      int predictor = 1;
      TIFFLZWDecoder? lzwDecoder;

      switch (compression) {
        case TiffConstants.compressionNone:
        case TiffConstants.compressionLzw:
        case TiffConstants.compressionPackbits:
        case TiffConstants.compressionDeflate:
        case TiffConstants.compressionAdobeDeflate:
        case TiffConstants.compressionOjpeg:
        case TiffConstants.compressionJpeg:
          break;
        default:
          throw IoException(
              IoExceptionMessageConstant.compressionIsNotSupported);
      }

      int photometric =
          dir.getFieldAsLong(TiffConstants.tifftagPhotometric).toInt();
      switch (photometric) {
        case TiffConstants.photometricMiniswhite:
        case TiffConstants.photometricMinisblack:
        case TiffConstants.photometricRgb:
        case TiffConstants.photometricSeparated:
        case TiffConstants.photometricPalette:
          break;
        default:
          if (compression != TiffConstants.compressionOjpeg &&
              compression != TiffConstants.compressionJpeg) {
            throw IoException(
                IoExceptionMessageConstant.photometricIsNotSupported);
          }
          break;
      }

      double rotation = 0;
      if (dir.isTagPresent(TiffConstants.tifftagOrientation)) {
        int rot = dir.getFieldAsLong(TiffConstants.tifftagOrientation).toInt();
        if (rot == 3 || rot == 4)
          rotation = math.pi;
        else if (rot == 5 || rot == 8)
          rotation = math.pi / 2.0;
        else if (rot == 6 || rot == 7) rotation = -(math.pi / 2.0);
      }

      if (dir.isTagPresent(TiffConstants.tifftagPlanarconfig) &&
          dir.getFieldAsLong(TiffConstants.tifftagPlanarconfig) ==
              TiffConstants.planarconfigSeparate) {
        throw IoException(
            IoExceptionMessageConstant.planarImagesAreNotSupported);
      }

      int extraSamples = 0;
      if (dir.isTagPresent(TiffConstants.tifftagExtrasamples)) extraSamples = 1;

      int samplePerPixel = 1;
      if (dir.isTagPresent(TiffConstants.tifftagSamplesperpixel)) {
        samplePerPixel =
            dir.getFieldAsLong(TiffConstants.tifftagSamplesperpixel).toInt();
      }

      int bitsPerSample = 1;
      if (dir.isTagPresent(TiffConstants.tifftagBitspersample)) {
        bitsPerSample =
            dir.getFieldAsLong(TiffConstants.tifftagBitspersample).toInt();
      }

      switch (bitsPerSample) {
        case 1:
        case 2:
        case 4:
        case 8:
          break;
        default:
          throw IoException(
              IoExceptionMessageConstant.bitsPerSampleIsNotSupported);
      }

      int h = dir.getFieldAsLong(TiffConstants.tifftagImagelength).toInt();
      int w = dir.getFieldAsLong(TiffConstants.tifftagImagewidth).toInt();
      int resolutionUnit = TiffConstants.resunitInch;
      if (dir.isTagPresent(TiffConstants.tifftagResolutionunit)) {
        resolutionUnit =
            dir.getFieldAsLong(TiffConstants.tifftagResolutionunit).toInt();
      }
      int dpiX = _getDpi(
          dir.getField(TiffConstants.tifftagXresolution), resolutionUnit);
      int dpiY = _getDpi(
          dir.getField(TiffConstants.tifftagYresolution), resolutionUnit);

      int fillOrder = 1;
      TiffField? fillOrderField = dir.getField(TiffConstants.tifftagFillorder);
      if (fillOrderField != null) fillOrder = fillOrderField.getAsInt(0);
      bool reverse = (fillOrder == TiffConstants.fillorderLsb2msb);

      int rowsStrip = h;
      if (dir.isTagPresent(TiffConstants.tifftagRowsperstrip)) {
        rowsStrip =
            dir.getFieldAsLong(TiffConstants.tifftagRowsperstrip).toInt();
      }
      if (rowsStrip <= 0 || rowsStrip > h) rowsStrip = h;

      List<int>? offset =
          _getArrayLongShort(dir, TiffConstants.tifftagStripoffsets);
      List<int>? size =
          _getArrayLongShort(dir, TiffConstants.tifftagStripbytecounts);

      if ((size == null ||
              (size.length == 1 &&
                  (size[0] == 0 || size[0] + offset![0] > s.length()))) &&
          h == rowsStrip) {
        size = [s.length() - offset![0]];
      }

      if (compression == TiffConstants.compressionLzw ||
          compression == TiffConstants.compressionDeflate ||
          compression == TiffConstants.compressionAdobeDeflate) {
        TiffField? predictorField =
            dir.getField(TiffConstants.tifftagPredictor);
        if (predictorField != null) {
          predictor = predictorField.getAsInt(0);
          if (predictor != 1 && predictor != 2) {
            throw IoException(
                IoExceptionMessageConstant.illegalValueForPredictorInTiffFile);
          }
          if (predictor == 2 && bitsPerSample != 8) {
            throw IoException(IoExceptionMessageConstant
                .bitSamplesAreNotSupportedForHorizontalDifferencingPredictor);
          }
        }
      }

      if (compression == TiffConstants.compressionLzw) {
        lzwDecoder = TIFFLZWDecoder(w, predictor, samplePerPixel);
      }

      int rowsLeft = h;
      BytesBuilder stream = BytesBuilder();
      BytesBuilder mstream = BytesBuilder();

      CCITTG4Encoder? g4;
      if (bitsPerSample == 1 &&
          samplePerPixel == 1 &&
          photometric != TiffConstants.photometricPalette) {
        g4 = CCITTG4Encoder(w);
      }

      if (compression == TiffConstants.compressionOjpeg) {
        if (!dir.isTagPresent(TiffConstants.tifftagJpegifoffset)) {
          throw IoException(
              IoExceptionMessageConstant.missingTagsForOjpegCompression);
        }
        int jpegOffset =
            dir.getFieldAsLong(TiffConstants.tifftagJpegifoffset).toInt();
        int jpegLength = s.length() - jpegOffset;
        if (dir.isTagPresent(TiffConstants.tifftagJpegifbytecount)) {
          jpegLength =
              dir.getFieldAsLong(TiffConstants.tifftagJpegifbytecount).toInt() +
                  size![0];
        }
        Uint8List jpeg =
            Uint8List(math.min(jpegLength, s.length() - jpegOffset));
        s.seek(jpegOffset);
        s.readFully(jpeg);
        tiff.image.setData(jpeg);
        tiff.image.setOriginalType(ImageType.JPEG);
        JpegImageHelper.processImage(tiff.image);
        tiff.jpegProcessing = true;
      } else if (compression == TiffConstants.compressionJpeg) {
        if (size!.length > 1) {
          throw IoException(IoExceptionMessageConstant
              .compressionJpegIsOnlySupportedWithASingleStripThisImageHasStrips);
        }
        Uint8List jpeg = Uint8List(size[0]);
        s.seek(offset![0]);
        s.readFully(jpeg);

        TiffField? jpegtables = dir.getField(TiffConstants.tifftagJpegtables);
        if (jpegtables != null) {
          Uint8List temp = jpegtables.getAsBytes();
          int tableoffset = 0;
          int tablelength = temp.length;
          if (temp.length >= 2 && temp[0] == 0xFF && temp[1] == 0xD8) {
            tableoffset = 2;
            tablelength -= 2;
          }
          if (temp.length >= 2 &&
              temp[temp.length - 2] == 0xFF &&
              temp[temp.length - 1] == 0xD9) {
            tablelength -= 2;
          }
          BytesBuilder combined = BytesBuilder();
          combined.add(jpeg.sublist(0, 2));
          combined.add(temp.sublist(tableoffset, tableoffset + tablelength));
          combined.add(jpeg.sublist(2));
          jpeg = combined.toBytes();
        }
        tiff.image.setData(jpeg);
        tiff.image.setOriginalType(ImageType.JPEG);
        JpegImageHelper.processImage(tiff.image);
        tiff.jpegProcessing = true;
        if (photometric == TiffConstants.photometricRgb) {
          tiff.image.setColorTransform(0);
        }
      } else {
        for (int k = 0; k < offset!.length; ++k) {
          Uint8List im = Uint8List(size![k]);
          s.seek(offset[k]);
          s.readFully(im);
          int height = math.min(rowsStrip, rowsLeft);
          Uint8List? outBuf;
          if (compression != TiffConstants.compressionNone) {
            outBuf = Uint8List(
                ((w * bitsPerSample * samplePerPixel + 7) ~/ 8) * height);
          }
          if (reverse) {
            TIFFFaxDecoder.reverseBits(im);
          }
          switch (compression) {
            case TiffConstants.compressionDeflate:
            case TiffConstants.compressionAdobeDeflate:
              var decoded = ZLibDecoder().convert(im);
              if (outBuf != null) {
                outBuf.setAll(0, decoded);
                _applyPredictor(outBuf, predictor, w, height, samplePerPixel);
              }
              break;
            case TiffConstants.compressionNone:
              outBuf = im;
              break;
            case TiffConstants.compressionPackbits:
              _decodePackbits(im, outBuf!);
              break;
            case TiffConstants.compressionLzw:
              lzwDecoder!.decode(im, outBuf!, height);
              break;
          }

          if (bitsPerSample == 1 &&
              samplePerPixel == 1 &&
              photometric != TiffConstants.photometricPalette) {
            g4!.fax4EncodeHeight(outBuf!, height);
          } else {
            if (extraSamples > 0) {
              _processExtraSamples(stream, mstream, outBuf!, samplePerPixel,
                  bitsPerSample, w, height);
            } else {
              stream.add(outBuf!);
            }
          }
          rowsLeft -= rowsStrip;
        }

        if (bitsPerSample == 1 &&
            samplePerPixel == 1 &&
            photometric != TiffConstants.photometricPalette) {
          RawImageHelper.updateRawImageParametersCCITT(
              tiff.image,
              w,
              h,
              false,
              RawImageData.ccittg4,
              photometric == TiffConstants.photometricMinisblack
                  ? RawImageData.ccittBlackis1
                  : 0,
              g4!.close(),
              null);
        } else {
          Uint8List compressedData =
              Uint8List.fromList(ZLibEncoder().convert(stream.toBytes()));
          RawImageHelper.updateRawImageParametersBasic(tiff.image, w, h,
              samplePerPixel - extraSamples, bitsPerSample, compressedData);
          tiff.image.setDeflated(true);
          if (extraSamples > 0) {
            RawImageData mimg =
                ImageDataFactory.createRawImage(null) as RawImageData;
            RawImageHelper.updateRawImageParametersBasic(
                mimg,
                w,
                h,
                1,
                bitsPerSample,
                Uint8List.fromList(ZLibEncoder().convert(mstream.toBytes())));
            mimg.makeMask();
            mimg.setDeflated(true);
            tiff.image.setImageMask(mimg);
          }
        }
      }

      tiff.image.setDpi(dpiX, dpiY);
      if (compression != TiffConstants.compressionOjpeg &&
          compression != TiffConstants.compressionJpeg) {
        if (dir.isTagPresent(TiffConstants.tifftagIccprofile)) {
          try {
            TiffField fd = dir.getField(TiffConstants.tifftagIccprofile)!;
            IccProfile iccProf = IccProfile.getInstance(fd.getAsBytes());
            if (samplePerPixel - extraSamples == iccProf.getNumComponents()) {
              tiff.image.setProfile(iccProf);
            }
          } catch (e) {
            // ignore
          }
        }
        if (dir.isTagPresent(TiffConstants.tifftagColormap)) {
          TiffField fd = dir.getField(TiffConstants.tifftagColormap)!;
          List<int> rgb = fd.getAsChars();
          Uint8List palette = Uint8List(rgb.length);
          int gColor = rgb.length ~/ 3;
          int bColor = gColor * 2;
          bool colormapBroken = true;

          for (int k = 0; k < gColor; ++k) {
            palette[k * 3] = (rgb[k] >> 8);
            palette[k * 3 + 1] = (rgb[k + gColor] >> 8);
            palette[k * 3 + 2] = (rgb[k + bColor] >> 8);
          }

          for (int k = 0; k < palette.length; ++k) {
            if (palette[k] != 0) {
              colormapBroken = false;
              break;
            }
          }

          if (colormapBroken) {
            for (int k = 0; k < gColor; ++k) {
              palette[k * 3] = rgb[k] & 0xFF;
              palette[k * 3 + 1] = rgb[k + gColor] & 0xFF;
              palette[k * 3 + 2] = rgb[k + bColor] & 0xFF;
            }
          }

          List<Object> indexed = [];
          indexed.add("/Indexed");
          indexed.add("/DeviceRGB");
          indexed.add(gColor - 1);
          indexed.add(PdfEncodings.convertToString(palette, null));

          tiff.additional = {"ColorSpace": indexed};
        }
      }
      if (photometric == TiffConstants.photometricMiniswhite) {
        tiff.image.setInverted(true);
      }
      if (rotation != 0) {
        tiff.image.setRotation(rotation);
      }
    } catch (e) {
      throw IoException(IoExceptionMessageConstant.cannotGetTiffImageColor, e);
    }
  }

  static int _getDpi(TiffField? fd, int resolutionUnit) {
    if (fd == null) return 0;
    List<int> res = fd.getAsRational(0);
    double frac = res[0] / res[1];
    int dpi = 0;
    switch (resolutionUnit) {
      case TiffConstants.resunitInch:
      case TiffConstants.resunitNone:
        dpi = (frac + 0.5).toInt();
        break;
      case TiffConstants.resunitCentimeter:
        dpi = (frac * 2.54 + 0.5).toInt();
        break;
    }
    return dpi;
  }

  static List<int>? _getArrayLongShort(TiffDirectory dir, int tag) {
    TiffField? field = dir.getField(tag);
    if (field == null) return null;
    if (field.getType() == TiffField.tiffLong) {
      return field.getAsLongs();
    }
    // Short
    List<int> chars = field.getAsChars();
    return chars;
  }

  static void _decodePackbits(Uint8List data, Uint8List dst) {
    int srcCount = 0;
    int dstCount = 0;
    int b;

    try {
      while (dstCount < dst.length && srcCount < data.length) {
        b = data[srcCount++];
        if (b <= 127) {
          int count = b + 1;
          for (int i = 0; i < count; i++) {
            dst[dstCount++] = data[srcCount++];
          }
        } else if (b != 128) {
          int repeat = data[srcCount++];
          int count = (256 - b) + 1;
          for (int i = 0; i < count; i++) {
            dst[dstCount++] = repeat;
          }
        }
      }
    } catch (e) {
      // ignore
    }
  }

  static void _applyPredictor(
      Uint8List uncompData, int predictor, int w, int h, int samplesPerPixel) {
    if (predictor != 2) return;
    int count;
    for (int j = 0; j < h; j++) {
      count = samplesPerPixel * (j * w + 1);
      for (int i = samplesPerPixel; i < w * samplesPerPixel; i++) {
        uncompData[count] =
            (uncompData[count] + uncompData[count - samplesPerPixel]) & 0xFF;
        count++;
      }
    }
  }

  static void _processExtraSamples(
      BytesBuilder zip,
      BytesBuilder mzip,
      Uint8List outBuf,
      int samplePerPixel,
      int bitsPerSample,
      int width,
      int height) {
    if (bitsPerSample == 8) {
      Uint8List mask = Uint8List(width * height);
      int mptr = 0;
      int optr = 0;
      int total = width * height * samplePerPixel;
      for (int k = 0; k < total; k += samplePerPixel) {
        for (int s = 0; s < samplePerPixel - 1; ++s) {
          outBuf[optr++] = outBuf[k + s];
        }
        mask[mptr++] = outBuf[k + samplePerPixel - 1];
      }
      zip.add(outBuf.sublist(0, optr));
      mzip.add(mask.sublist(0, mptr));
    } else {
      throw IoException(IoExceptionMessageConstant.extraSamplesAreNotSupported);
    }
  }
}
