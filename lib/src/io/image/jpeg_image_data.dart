import 'dart:typed_data';
import 'package:dpdf/src/io/image/image_data.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';

class CraftJpegImageData extends CraftImageData {
  CraftJpegImageData.fromUrl(Uri url) : super.fromUrl(url, CraftImageType.JPEG);
  CraftJpegImageData.fromBytes(Uint8List bytes)
      : super.fromBytes(bytes, CraftImageType.JPEG);
}
