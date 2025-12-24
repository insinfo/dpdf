import 'dart:typed_data';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'raw_image_data.dart';

/// BMP image data class.
class BmpImageData extends RawImageData {
  /// Indicates that the source image does not have a header.
  final bool noHeader;

  /// Creates a BmpImageData from a URL.
  BmpImageData.fromUrl(Uri url, {this.noHeader = false})
      : super.fromUrl(url, ImageType.BMP);

  /// Creates a BmpImageData from bytes.
  BmpImageData.fromBytes(Uint8List data, {this.noHeader = false})
      : super.fromBytes(data, ImageType.BMP);

  /// Returns true if the bitmap image does not contain a header.
  bool isNoHeader() => noHeader;
}
