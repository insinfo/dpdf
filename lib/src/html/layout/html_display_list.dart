import '../css/css_color.dart';
import '../model/html_box.dart';
import '../model/html_raster_image.dart';

/// Platform-neutral output of the HTML layout stage, consumed by PDF paint.
class CraftHtmlDisplayList {
  final List<CraftHtmlTextFragment> textFragments;
  final List<CraftHtmlBoxDecoration> boxDecorations;
  final List<CraftHtmlImageFragment> imageFragments;
  const CraftHtmlDisplayList(this.textFragments, this.boxDecorations,
      [this.imageFragments = const []]);
}

/// Positioned raster image command. Images are atomic in the flow profile.
class CraftHtmlImageFragment {
  final CraftHtmlRasterImage image;
  final double x;
  final double top;
  final double width;
  final double height;
  const CraftHtmlImageFragment(
      this.image, this.x, this.top, this.width, this.height);
}

class CraftHtmlTextFragment {
  final String text;
  final CraftHtmlTextStyle style;
  final double x;
  final double baseline;

  /// URI from a source HTML anchor. Null means ordinary non-interactive text.
  final String? linkTarget;
  const CraftHtmlTextFragment(this.text, this.style, this.x, this.baseline,
      {this.linkTarget});
}

/// Background and border paint command in top-down document coordinates.
class CraftHtmlBoxDecoration {
  final double x;
  final double top;
  final double width;
  final double height;
  final CraftCssColor? backgroundColor;
  final CraftHtmlBorder? border;
  const CraftHtmlBoxDecoration({
    required this.x,
    required this.top,
    required this.width,
    required this.height,
    this.backgroundColor,
    this.border,
  });
}
