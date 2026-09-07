import 'dart:typed_data';
import 'package:dpdf/src/layout/properties/image_type.dart';
import 'package:dpdf/src/io/codec/tiff_directory.dart';
import 'package:dpdf/src/io/source/random_access_file_or_array.dart';
import 'raw_image_data.dart';

/// TIFF image data class.
class CraftTiffImageData extends CraftRawImageData {
  /// Whether to try to recover from image processing errors.
  final bool recoverFromImageError;

  /// The page number within the TIFF (1-indexed).
  final int page;

  /// Whether to use direct color model.
  final bool direct;

  /// Creates a TiffImageData from a URL.
  CraftTiffImageData.fromUrl(
    Uri url, {
    this.recoverFromImageError = false,
    this.page = 1,
    this.direct = false,
  }) : super.fromUrl(url, CraftImageType.TIFF);

  /// Creates a TiffImageData from bytes.
  CraftTiffImageData.fromBytes(
    Uint8List data, {
    this.recoverFromImageError = false,
    this.page = 1,
    this.direct = false,
  }) : super.fromBytes(data, CraftImageType.TIFF);

  /// Returns whether to recover from image errors.
  bool isRecoverFromImageError() => recoverFromImageError;

  /// Gets the page number.
  int pageAt() => page;

  /// Returns whether direct color model is used.
  bool isDirect() => direct;

  /// Sets the original type of the image.
  void setOriginalType(CraftImageType type) {
    originalType = type;
  }

  /// Gets the number of pages in the TIFF file.
  static int pageTotal(CraftRandomAccessFileOrArray raf) {
    return TiffDirectory.getNumDirectories(raf);
  }
}
