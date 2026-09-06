import 'dart:typed_data';

import 'package:dpdf/src/io/image/raw_image_data.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';

class BmpImageData extends RawImageData {
  final bool noHeader;

  BmpImageData.fromUrl(Uri url, {this.noHeader = false})
      : super.fromUrl(url, ImageType.BMP);

  BmpImageData.fromBytes(Uint8List bytes, {this.noHeader = false})
      : super.fromBytes(bytes, ImageType.BMP);

  bool isNoHeader() => noHeader;
}
