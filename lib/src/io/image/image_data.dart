import 'dart:typed_data';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

abstract class ImageData {
  static int _serialId = 0;

  Uri? url;
  List<int>? transparency;
  ImageType? originalType;
  double width = 0;
  double height = 0;
  Uint8List? data;
  int imageSize = 0;
  int bpc = 1;
  int colorEncodingComponentsNumber = -1;
  List<double>? decode;
  Map<String, Object>? decodeParms;
  bool inverted = false;
  double rotation = 0;
  // IccProfile? profile; // TODO: Implement IccProfile
  int dpiX = 0;
  int dpiY = 0;
  int colorTransform = 1;
  bool deflated = false;
  bool mask = false;
  ImageData? imageMask;
  bool interpolation = false;
  double xyRatio = 0;
  String? filter;
  Map<String, Object>? imageAttributes;
  late final int mySerialId;

  ImageData.fromUrl(this.url, this.originalType) {
    mySerialId = _getNextSerialId();
  }

  ImageData.fromBytes(this.data, this.originalType) {
    mySerialId = _getNextSerialId();
  }

  static int _getNextSerialId() {
    return ++_serialId;
  }

  bool isRawImage() => false;

  bool canBeMask() {
    if (isRawImage()) {
      if (bpc > 0xff) return true;
    }
    return colorEncodingComponentsNumber == 1;
  }

  void makeMask() {
    if (!canBeMask()) {
      throw IoException(
          IoExceptionMessageConstant.thisImageCanNotBeAnImageMask);
    }
    mask = true;
  }

  void setImageMask(ImageData mask) {
    if (this.mask) {
      throw IoException(
          IoExceptionMessageConstant.imageMaskCannotContainAnotherImageMask);
    }
    if (!mask.mask) {
      throw IoException(IoExceptionMessageConstant
          .imageIsNotAMaskYouMustCallImageDataMakeMask);
    }
    this.imageMask = mask;
  }

  Uint8List? getData() => data;

  // TODO: LoadData from URL using RandomAccessFileOrArray
}
