import '../css/css_values.dart';
import '../css/css_color.dart';
import 'html_raster_image.dart';
import 'html_svg_image.dart';

/// The normalized box tree consumed by the HTML layout engines.
///
/// It deliberately contains no `package:html` types: parsing, CSS resolution,
/// layout and PDF painting remain independently testable layers.
enum HtmlDisplay { inline, block, flex, grid, none }

/// Main-axis distribution supported by the portable flex layout profile.
enum HtmlJustifyContent { start, center, end, spaceBetween }

enum HtmlTextAlign { start, center, end, justify }

/// Structural roles consumed by the portable table layout pass.
enum HtmlBoxRole { normal, table, tableRow, tableHeaderCell, tableCell }

class HtmlTextStyle {
  final double fontSize;

  /// CSS font-family list inherited by descendant text boxes.
  final String? fontFamily;
  final bool bold;
  final bool italic;
  final CssColor color;

  const HtmlTextStyle(this.fontSize,
      {this.fontFamily,
      this.bold = false,
      this.italic = false,
      this.color = CssColor.black});
}

class HtmlBorder {
  final double width;
  final CssColor color;
  const HtmlBorder(this.width, this.color);
  bool get visible => width > 0;
}

class HtmlBoxStyle {
  final HtmlDisplay display;
  final HtmlTextStyle text;
  final String flexDirection;
  final bool flexWrap;
  final HtmlJustifyContent justifyContent;
  final bool hasJustifyContent;
  final String? gridTemplateColumns;
  final double gap;
  final CssLength width;
  final CssEdges margin;
  final CssEdges padding;
  final HtmlTextAlign textAlign;
  final CssColor? backgroundColor;
  final HtmlBorder? border;

  const HtmlBoxStyle({
    required this.display,
    required this.text,
    this.flexDirection = 'row',
    this.flexWrap = false,
    this.justifyContent = HtmlJustifyContent.start,
    this.hasJustifyContent = false,
    this.gridTemplateColumns,
    this.gap = 0,
    this.width = const CssLength.auto(),
    this.margin = const CssEdges.zero(),
    this.padding = const CssEdges.zero(),
    this.textAlign = HtmlTextAlign.start,
    this.backgroundColor,
    this.border,
  });
}

class HtmlBox {
  final HtmlBoxStyle style;
  final String? text;

  /// URI inherited from an HTML anchor for visible link content.
  final String? linkTarget;
  final HtmlRasterImage? image;
  final HtmlSvgImage? svg;
  final HtmlBoxRole role;
  final List<HtmlBox> children;

  const HtmlBox({
    required this.style,
    this.text,
    this.linkTarget,
    this.image,
    this.svg,
    this.role = HtmlBoxRole.normal,
    this.children = const [],
  });

  bool get isText => text != null;
  bool get isImage => image != null;
  bool get isSvg => svg != null;

  String get textContent =>
      text ?? children.map((child) => child.textContent).join(' ');
}
