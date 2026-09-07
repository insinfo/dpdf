import '../../io/image/image_data.dart';

/// Decoded raster image and its layout dimensions in PDF points.
class CraftHtmlRasterImage {
  final CraftImageData image;
  final double width;
  final double height;
  const CraftHtmlRasterImage(this.image, this.width, this.height);
}
