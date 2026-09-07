import 'dart:typed_data';

import 'package:dpdf/src/io/image/raw_image_data.dart';
import 'package:dpdf/src/layout/properties/image_type.dart';

class CraftBmpImageData extends CraftRawImageData {
  final bool noHeader;

  CraftBmpImageData.fromUrl(Uri url, {this.noHeader = false})
      : super.fromUrl(url, CraftImageType.BMP);

  CraftBmpImageData.fromBytes(Uint8List bytes, {this.noHeader = false})
      : super.fromBytes(bytes, CraftImageType.BMP);

  bool isNoHeader() => noHeader;
}
