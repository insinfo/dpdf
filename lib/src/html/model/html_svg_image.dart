/// Inline SVG kept as vector source until the PDF painting stage.
class HtmlSvgImage {
  final String source;
  final double width;
  final double height;

  const HtmlSvgImage(this.source, this.width, this.height);
}
