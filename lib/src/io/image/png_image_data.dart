import 'dart:typed_data';
import 'package:pdfcraft/src/io/image/image_data.dart';
import 'package:pdfcraft/src/layout/properties/image_type.dart';

class CraftPngImageData extends CraftImageData {
  CraftImageData? smask;

  CraftPngImageData.fromBytes(Uint8List bytes)
      : super.fromBytes(bytes, CraftImageType.PNG);
  CraftPngImageData.fromUrl(Uri url) : super.fromUrl(url, CraftImageType.PNG);
}
