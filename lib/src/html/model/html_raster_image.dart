import '../../io/image/image_data.dart';

/// Decoded raster image and its layout dimensions in PDF points.
class HtmlRasterImage {
  final ImageData image;
  final double width;
  final double height;
  const HtmlRasterImage(this.image, this.width, this.height);
}
