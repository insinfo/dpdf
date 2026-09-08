import '../css/css_color.dart';
import '../model/html_box.dart';
import '../model/html_raster_image.dart';
import '../model/html_svg_image.dart';

/// Platform-neutral output of the HTML layout stage, consumed by PDF paint.
class HtmlDisplayList {
  final List<HtmlTextFragment> textFragments;
  final List<HtmlBoxDecoration> boxDecorations;
  final List<HtmlImageFragment> imageFragments;
  final List<HtmlSvgFragment> svgFragments;
  const HtmlDisplayList(this.textFragments, this.boxDecorations,
      [this.imageFragments = const [], this.svgFragments = const []]);
}

/// Positioned vector SVG command. SVG remains vector data in the PDF.
class HtmlSvgFragment {
  final HtmlSvgImage image;
  final double x;
  final double top;
  final double width;
  final double height;
  const HtmlSvgFragment(this.image, this.x, this.top, this.width, this.height);
}

/// Positioned raster image command. Images are atomic in the flow profile.
class HtmlImageFragment {
  final HtmlRasterImage image;
  final double x;
  final double top;
  final double width;
  final double height;
  const HtmlImageFragment(
      this.image, this.x, this.top, this.width, this.height);
}

class HtmlTextFragment {
  final String text;
  final HtmlTextStyle style;
  final double x;
  final double baseline;

  /// URI from a source HTML anchor. Null means ordinary non-interactive text.
  final String? linkTarget;
  const HtmlTextFragment(this.text, this.style, this.x, this.baseline,
      {this.linkTarget});
}

/// Background and border paint command in top-down document coordinates.
class HtmlBoxDecoration {
  final double x;
  final double top;
  final double width;
  final double height;
  final CssColor? backgroundColor;
  final HtmlBorder? border;
  const HtmlBoxDecoration({
    required this.x,
    required this.top,
    required this.width,
    required this.height,
    this.backgroundColor,
    this.border,
  });
}
