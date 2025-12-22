import 'dart:typed_data';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';

abstract class ImageData {
  static int _serialId = 0;

  Uri? url;
  List<int>? transparency;
  ImageType? originalType;
  int colorType = -1;
  Uint8List? colorPalette;
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
  bool hasCHRM = false;
  double gamma = 0.0;
  // PngChromaticities? pngChromaticities; // TODO
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

  ImageType? getOriginalType() => originalType;

  void setProfile(dynamic profile) {
    // this.profile = profile;
  }

  bool isIndexed() => colorType == 3;

  bool isGrayscaleImage() => colorType == 0 || colorType == 4;

  void setColorType(int colorType) => this.colorType = colorType;

  int getColorType() => colorType;

  void setColorPalette(Uint8List palette) => colorPalette = palette;

  void setDpi(int dpiX, int dpiY) {
    this.dpiX = dpiX;
    this.dpiY = dpiY;
  }

  void setXYRatio(double xyRatio) => this.xyRatio = xyRatio;

  void setGamma(double gamma) => this.gamma = gamma;

  void setPngChromaticities(dynamic chrom) {
    hasCHRM = true;
    // this.pngChromaticities = chrom;
  }

  bool isHasCHRM() => hasCHRM;

  void setDeflated(bool deflated) => this.deflated = deflated;

  // TODO: LoadData from URL using RandomAccessFileOrArray
}
