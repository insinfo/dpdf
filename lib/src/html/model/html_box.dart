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

/// Lines drawn with the text by `text-decoration` (CSS 2.1 §16.3.1).
enum HtmlTextDecoration { underline, overline, lineThrough }

class HtmlTextStyle {
  final double fontSize;

  /// CSS font-family list inherited by descendant text boxes.
  final String? fontFamily;
  final bool bold;
  final bool italic;
  final CssColor color;

  /// `line-height` given as a number, which inherits as the factor itself
  /// rather than as the length it produced (CSS 2.1 §10.8.1).
  final double? lineHeightFactor;

  /// `line-height` given as a length or a percentage, already computed into
  /// points; it inherits as that computed length.
  final double? lineHeightLength;

  /// Decoration lines propagated to the text of this box and its descendants.
  final Set<HtmlTextDecoration> decoration;

  const HtmlTextStyle(this.fontSize,
      {this.fontFamily,
      this.bold = false,
      this.italic = false,
      this.color = CssColor.black,
      this.lineHeightFactor,
      this.lineHeightLength,
      this.decoration = const <HtmlTextDecoration>{}});

  /// Height of the line box this text sits in.
  ///
  /// `normal` is 1.35 times the font size, the ratio the flow engine has
  /// always used for its line boxes.
  double get lineHeight =>
      lineHeightLength ?? fontSize * (lineHeightFactor ?? 1.35);
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

  /// Explicit content height (CSS 2.1 §10.5). A percentage needs a
  /// containing block whose height is known, which the flow profile never
  /// establishes, so only absolute lengths take effect.
  final CssLength height;
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
    this.height = const CssLength.auto(),
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
