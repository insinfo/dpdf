import 'dart:typed_data';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'package:dpdf/src/io/exceptions/io_exception.dart';
import 'package:dpdf/src/io/exceptions/io_exception_message_constant.dart';
import '../colors/icc_profile.dart';

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
  IccProfile? profile;
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
  // PngChromaticities? pngChromaticities; // Stub for PngChromaticities
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

  void setProfile(IccProfile profile) {
    this.profile = profile;
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

  bool isDeflated() => deflated;

  void setColorEncodingComponentsNumber(int n) =>
      colorEncodingComponentsNumber = n;
  int getColorEncodingComponentsNumber() => colorEncodingComponentsNumber;

  void setBpc(int bpc) => this.bpc = bpc;
  int getBpc() => bpc;

  void setFilter(String filter) => this.filter = filter;
  String? getFilter() => filter;

  void setDecodeParms(Map<String, Object>? decodeParms) =>
      this.decodeParms = decodeParms;
  Map<String, Object>? getDecodeParms() => decodeParms;

  void setDecode(List<double>? decode) => this.decode = decode;
  List<double>? getDecode() => decode;

  bool isInverted() => inverted;
  void setInverted(bool inverted) => this.inverted = inverted;

  void setImageAttributes(Map<String, Object> attributes) =>
      imageAttributes = attributes;

  bool isMask() => mask;

  double getWidth() => width;
  void setWidth(double width) => this.width = width;

  double getHeight() => height;
  void setHeight(double height) => this.height = height;

  void setData(Uint8List? data) => this.data = data;

  void setTransparency(List<int>? transparency) =>
      this.transparency = transparency;

  void setColorTransform(int transform) => colorTransform = transform;

  void setRotation(double rotation) => this.rotation = rotation;

  bool canImageBeInline() => true;

  // Data loading is handled by ImageDataFactory.createFromUrl
}
