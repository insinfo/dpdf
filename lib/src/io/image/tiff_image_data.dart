import 'dart:typed_data';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'raw_image_data.dart';

/// TIFF image data class.
class TiffImageData extends RawImageData {
  /// Whether to try to recover from image processing errors.
  final bool recoverFromImageError;

  /// The page number within the TIFF (1-indexed).
  final int page;

  /// Whether to use direct color model.
  final bool direct;

  /// Creates a TiffImageData from a URL.
  TiffImageData.fromUrl(
    Uri url, {
    this.recoverFromImageError = false,
    this.page = 1,
    this.direct = false,
  }) : super.fromUrl(url, ImageType.TIFF);

  /// Creates a TiffImageData from bytes.
  TiffImageData.fromBytes(
    Uint8List data, {
    this.recoverFromImageError = false,
    this.page = 1,
    this.direct = false,
  }) : super.fromBytes(data, ImageType.TIFF);

  /// Returns whether to recover from image errors.
  bool isRecoverFromImageError() => recoverFromImageError;

  /// Gets the page number.
  int getPage() => page;

  /// Returns whether direct color model is used.
  bool isDirect() => direct;

  /// Sets the original type of the image.
  void setOriginalType(ImageType type) {
    originalType = type;
  }

  // TODO: Add getNumberOfPages when TIFFDirectory is ported
}
