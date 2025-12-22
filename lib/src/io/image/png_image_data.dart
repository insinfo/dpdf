import 'dart:typed_data';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';

class PngImageData extends ImageData {
  PngImageData.fromBytes(Uint8List bytes)
      : super.fromBytes(bytes, ImageType.PNG);
  PngImageData.fromUrl(Uri url) : super.fromUrl(url, ImageType.PNG);
}
