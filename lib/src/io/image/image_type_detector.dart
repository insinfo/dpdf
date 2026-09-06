import 'dart:typed_data';
import 'package:dpdf/src/layout/properties/image_type.dart';

class ImageTypeDetector {
  static const List<int> _gif = [71, 73, 70]; // GIF
  static const List<int> _jpeg = [0xFF, 0xD8];
  static const List<int> _jpeg2000_1 = [0x00, 0x00, 0x00, 0x0c];
  static const List<int> _jpeg2000_2 = [0xff, 0x4f, 0xff, 0x51];
  static const List<int> _png = [137, 80, 78, 71];
  static const List<int> _wmf = [0xD7, 0xCD];
  static const List<int> _bmp = [66, 77]; // BM
  static const List<int> _tiff_1 = [77, 77, 0, 42]; // MM
  static const List<int> _tiff_2 = [73, 73, 42, 0]; // II
  static const List<int> _jbig2 = [0x97, 74, 66, 50, 13, 10, 0x1a, 10];

  ImageTypeDetector._();

  static ImageType detectImageType(Uint8List source) {
    if (source.length < 8) return ImageType.NONE;
    return _detectImageTypeByHeader(source);
  }

  static ImageType _detectImageTypeByHeader(Uint8List header) {
    if (_imageTypeIs(header, _gif)) return ImageType.GIF;
    if (_imageTypeIs(header, _jpeg)) return ImageType.JPEG;
    if (_imageTypeIs(header, _jpeg2000_1) || _imageTypeIs(header, _jpeg2000_2))
      return ImageType.JPEG2000;
    if (_imageTypeIs(header, _png)) return ImageType.PNG;
    if (_imageTypeIs(header, _bmp)) return ImageType.BMP;
    if (_imageTypeIs(header, _tiff_1) || _imageTypeIs(header, _tiff_2))
      return ImageType.TIFF;
    if (_imageTypeIs(header, _jbig2)) return ImageType.JBIG2;
    if (_imageTypeIs(header, _wmf)) return ImageType.WMF;

    return ImageType.NONE;
  }

  static bool _imageTypeIs(Uint8List header, List<int> compareWith) {
    if (header.length < compareWith.length) return false;
    for (int i = 0; i < compareWith.length; i++) {
      if (header[i] != compareWith[i]) return false;
    }
    return true;
  }
}
