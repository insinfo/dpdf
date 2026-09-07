import 'dart:convert';

import '../../io/image/image_data_factory.dart';
import '../../layout/properties/image_type.dart';
import '../model/html_raster_image.dart';

/// Decodes the narrow, portable image source profile accepted by HTML paint.
/// External URLs are intentionally not fetched by document conversion.
class HtmlDataImage {
  static HtmlRasterImage? tryParse(String? source,
      {String? width, String? height}) {
    if (source == null || !source.startsWith('data:')) return null;
    final comma = source.indexOf(',');
    if (comma < 0) return null;
    final header = source.substring(5, comma).trim().toLowerCase();
    final accepted = header == 'image/png;base64' ||
        header == 'image/jpeg;base64' ||
        header == 'image/jpg;base64';
    if (!accepted) return null;
    try {
      final image =
          ImageDataFactory.create(base64Decode(source.substring(comma + 1)));
      final type = image.getOriginalType();
      if (type != ImageType.PNG && type != ImageType.JPEG) {
        return null;
      }
      final naturalWidth = image.getWidth();
      final naturalHeight = image.getHeight();
      if (naturalWidth <= 0 || naturalHeight <= 0) return null;
      final requestedWidth = _positive(width);
      final requestedHeight = _positive(height);
      final resolvedWidth = requestedWidth ??
          (requestedHeight == null
              ? naturalWidth
              : naturalWidth * requestedHeight / naturalHeight);
      final resolvedHeight =
          requestedHeight ?? naturalHeight * resolvedWidth / naturalWidth;
      return HtmlRasterImage(image, resolvedWidth, resolvedHeight);
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static double? _positive(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    return parsed == null || !parsed.isFinite || parsed <= 0 ? null : parsed;
  }
}
