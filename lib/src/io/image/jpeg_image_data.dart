import 'dart:typed_data';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';

class JpegImageData extends ImageData {
  JpegImageData.fromUrl(Uri url) : super.fromUrl(url, ImageType.JPEG);
  JpegImageData.fromBytes(Uint8List bytes)
      : super.fromBytes(bytes, ImageType.JPEG);
}
