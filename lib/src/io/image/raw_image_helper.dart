import 'dart:typed_data';

import 'package:dpdf/src/io/codec/ccitt_g4_encoder.dart';
import 'package:dpdf/src/io/codec/tiff_fax_decoder.dart';
import 'package:dpdf/src/io/image/raw_image_data.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

class RawImageHelper {
  static void updateImageAttributes(
      RawImageData image, Map<String, Object>? additional) {
    if (!image.isRawImage()) {
      throw ArgumentError("Raw image expected.");
    }

    int colorSpace = image.getColorEncodingComponentsNumber();
    int typeCCITT = image.getTypeCcitt();

    if (typeCCITT > 0xff) {
      if (!image.isMask()) {
        image.setColorEncodingComponentsNumber(1);
      }
      image.setBpc(1);
      image.setFilter("CCITTFaxDecode");

      int k = typeCCITT - RawImageData.ccittg31d;
      Map<String, Object> decodeparms = {};
      if (k != 0) {
        decodeparms["K"] = k;
      }
      if ((colorSpace & RawImageData.ccittBlackis1) != 0) {
        decodeparms["BlackIs1"] = true;
      }
      if ((colorSpace & RawImageData.ccittEncodedbytealign) != 0) {
        decodeparms["EncodedByteAlign"] = true;
      }
      if ((colorSpace & RawImageData.ccittEndofline) != 0) {
        decodeparms["EndOfLine"] = true;
      }
      if ((colorSpace & RawImageData.ccittEndofblock) != 0) {
        decodeparms["EndOfBlock"] = false;
      }
      decodeparms["Columns"] = image.getWidth();
      decodeparms["Rows"] = image.getHeight();
      image.setDecodeParms(decodeparms);
    } else {
      switch (colorSpace) {
        case 1:
          if (image.isInverted()) {
            image.setDecode([1.0, 0.0]);
          }
          break;
        case 3:
          if (image.isInverted()) {
            image.setDecode([1.0, 0.0, 1.0, 0.0, 1.0, 0.0]);
          }
          break;
        case 4:
        default:
          if (image.isInverted()) {
            image.setDecode([1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0]);
          }
          break;
      }
      if (additional != null) {
        image.setImageAttributes(additional);
      }
      if (image.isMask() && (image.getBpc() == 1 || image.getBpc() > 8)) {
        image.setColorEncodingComponentsNumber(-1);
      }
      if (image.isDeflated()) {
        image.setFilter("FlateDecode");
      }
    }
  }

  static void updateRawImageParameters(RawImageData image, int width,
      int height, int components, int bpc, Uint8List data,
      [Uint8List? transparency]) {
    if (transparency != null && transparency.length != components * 2) {
      throw IoException(IoExceptionMessageConstant
          .transparencyLengthMustBeEqualTo2WithCcittImages);
    }

    if (components == 1 && bpc == 1) {
      // Compress with G4
      Uint8List g4 = CCITTG4Encoder.compress(data, width, height);
      updateRawImageParametersCCITT(image, width, height, false,
          RawImageData.ccittg4, RawImageData.ccittBlackis1, g4, transparency);
    } else {
      updateRawImageParametersBasic(
          image, width, height, components, bpc, data);
      image.setTransparency(transparency);
    }
  }

  static void updateRawImageParametersBasic(RawImageData image, int width,
      int height, int components, int bpc, Uint8List data) {
    image.setHeight(height.toDouble());
    image.setWidth(width.toDouble());
    if (components != 1 && components != 3 && components != 4) {
      throw IoException(IoExceptionMessageConstant.componentsMustBe134);
    }
    if (bpc != 1 && bpc != 2 && bpc != 4 && bpc != 8) {
      throw IoException(IoExceptionMessageConstant.bitsPerComponentMustBe1248);
    }
    image.setColorEncodingComponentsNumber(components);
    image.setBpc(bpc);
    image.setData(data);
  }

  static void updateRawImageParametersCCITT(
      RawImageData image,
      int width,
      int height,
      bool reverseBits,
      int typeCCITT,
      int parameters,
      Uint8List data,
      [Uint8List? transparency]) {
    if (transparency != null && transparency.length != 2) {
      throw IoException(IoExceptionMessageConstant
          .transparencyLengthMustBeEqualTo2WithCcittImages);
    }
    updateCcittImageParameters(
        image, width, height, reverseBits, typeCCITT, parameters, data);
    image.setTransparency(transparency);
  }

  static void updateCcittImageParameters(
      RawImageData image,
      int width,
      int height,
      bool reverseBits,
      int typeCcitt,
      int parameters,
      Uint8List data) {
    if (typeCcitt != RawImageData.ccittg4 &&
        typeCcitt != RawImageData.ccittg31d &&
        typeCcitt != RawImageData.ccittg32d) {
      throw IoException(IoExceptionMessageConstant
          .ccittCompressionTypeMustBeCcittg4Ccittg31dOrCcittg32d);
    }
    if (reverseBits) {
      TIFFFaxDecoder.reverseBits(data);
    }
    image.setHeight(height.toDouble());
    image.setWidth(width.toDouble());
    image.setColorEncodingComponentsNumber(parameters);
    image.setTypeCcitt(typeCcitt);
    image.setData(data);
  }
}
