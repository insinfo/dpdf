import 'dart:typed_data';

import 'package:dpdf/src/io/codec/ccitt_g4_encoder.dart';
import 'package:dpdf/src/io/codec/tiff_fax_decoder.dart';
import 'package:dpdf/src/io/image/raw_image_data.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

class CraftRawImageHelper {
  static void updateImageAttributes(
      CraftRawImageData image, Map<String, Object>? additional) {
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

      int k = typeCCITT - CraftRawImageData.ccittg31d;
      Map<String, Object> decodeparms = {};
      if (k != 0) {
        decodeparms["K"] = k;
      }
      if ((colorSpace & CraftRawImageData.ccittBlackis1) != 0) {
        decodeparms["BlackIs1"] = true;
      }
      if ((colorSpace & CraftRawImageData.ccittEncodedbytealign) != 0) {
        decodeparms["EncodedByteAlign"] = true;
      }
      if ((colorSpace & CraftRawImageData.ccittEndofline) != 0) {
        decodeparms["EndOfLine"] = true;
      }
      if ((colorSpace & CraftRawImageData.ccittEndofblock) != 0) {
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

  static void updateRawImageParameters(CraftRawImageData image, int width,
      int height, int components, int bpc, Uint8List data,
      [Uint8List? transparency]) {
    if (transparency != null && transparency.length != components * 2) {
      throw IoException(CraftIoExceptionMessageConstant
          .transparencyLengthMustBeEqualTo2WithCcittImages);
    }

    if (components == 1 && bpc == 1) {
      // Compress with G4
      Uint8List g4 = CraftCCITTG4Encoder.compress(data, width, height);
      updateRawImageParametersCCITT(
          image,
          width,
          height,
          false,
          CraftRawImageData.ccittg4,
          CraftRawImageData.ccittBlackis1,
          g4,
          transparency);
    } else {
      updateRawImageParametersBasic(
          image, width, height, components, bpc, data);
      image.setTransparency(transparency);
    }
  }

  static void updateRawImageParametersBasic(CraftRawImageData image, int width,
      int height, int components, int bpc, Uint8List data) {
    image.setHeight(height.toDouble());
    image.setWidth(width.toDouble());
    if (components != 1 && components != 3 && components != 4) {
      throw IoException(CraftIoExceptionMessageConstant.componentsMustBe134);
    }
    if (bpc != 1 && bpc != 2 && bpc != 4 && bpc != 8) {
      throw IoException(
          CraftIoExceptionMessageConstant.bitsPerComponentMustBe1248);
    }
    image.setColorEncodingComponentsNumber(components);
    image.setBpc(bpc);
    image.setData(data);
  }

  static void updateRawImageParametersCCITT(
      CraftRawImageData image,
      int width,
      int height,
      bool reverseBits,
      int typeCCITT,
      int parameters,
      Uint8List data,
      [Uint8List? transparency]) {
    if (transparency != null && transparency.length != 2) {
      throw IoException(CraftIoExceptionMessageConstant
          .transparencyLengthMustBeEqualTo2WithCcittImages);
    }
    updateCcittImageParameters(
        image, width, height, reverseBits, typeCCITT, parameters, data);
    image.setTransparency(transparency);
  }

  static void updateCcittImageParameters(
      CraftRawImageData image,
      int width,
      int height,
      bool reverseBits,
      int typeCcitt,
      int parameters,
      Uint8List data) {
    if (typeCcitt != CraftRawImageData.ccittg4 &&
        typeCcitt != CraftRawImageData.ccittg31d &&
        typeCcitt != CraftRawImageData.ccittg32d) {
      throw IoException(CraftIoExceptionMessageConstant
          .ccittCompressionTypeMustBeCcittg4Ccittg31dOrCcittg32d);
    }
    if (reverseBits) {
      CraftTIFFFaxDecoder.reverseBits(data);
    }
    image.setHeight(height.toDouble());
    image.setWidth(width.toDouble());
    image.setColorEncodingComponentsNumber(parameters);
    image.setTypeCcitt(typeCcitt);
    image.setData(data);
  }
}
