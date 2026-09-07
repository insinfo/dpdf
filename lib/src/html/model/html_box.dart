import '../css/css_values.dart';
import '../css/css_color.dart';

/// The normalized box tree consumed by the HTML layout engines.
///
/// It deliberately contains no `package:html` types: parsing, CSS resolution,
/// layout and PDF painting remain independently testable layers.
enum CraftHtmlDisplay { inline, block, flex, grid, none }

/// Main-axis distribution supported by the portable flex layout profile.
enum CraftHtmlJustifyContent { start, center, end, spaceBetween }

enum CraftHtmlTextAlign { start, center, end, justify }

class CraftHtmlTextStyle {
  final double fontSize;

  /// CSS font-family list inherited by descendant text boxes.
  final String? fontFamily;
  final bool bold;
  final bool italic;
  final CraftCssColor color;

  const CraftHtmlTextStyle(this.fontSize,
      {this.fontFamily,
      this.bold = false,
      this.italic = false,
      this.color = CraftCssColor.black});
}

class CraftHtmlBorder {
  final double width;
  final CraftCssColor color;
  const CraftHtmlBorder(this.width, this.color);
  bool get visible => width > 0;
}

class CraftHtmlBoxStyle {
  final CraftHtmlDisplay display;
  final CraftHtmlTextStyle text;
  final String flexDirection;
  final bool flexWrap;
  final CraftHtmlJustifyContent justifyContent;
  final bool hasJustifyContent;
  final String? gridTemplateColumns;
  final double gap;
  final CraftCssLength width;
  final CraftCssEdges margin;
  final CraftCssEdges padding;
  final CraftHtmlTextAlign textAlign;
  final CraftCssColor? backgroundColor;
  final CraftHtmlBorder? border;

  const CraftHtmlBoxStyle({
    required this.display,
    required this.text,
    this.flexDirection = 'row',
    this.flexWrap = false,
    this.justifyContent = CraftHtmlJustifyContent.start,
    this.hasJustifyContent = false,
    this.gridTemplateColumns,
    this.gap = 0,
    this.width = const CraftCssLength.auto(),
    this.margin = const CraftCssEdges.zero(),
    this.padding = const CraftCssEdges.zero(),
    this.textAlign = CraftHtmlTextAlign.start,
    this.backgroundColor,
    this.border,
  });
}

class CraftHtmlBox {
  final CraftHtmlBoxStyle style;
  final String? text;

  /// URI inherited from an HTML anchor for visible link content.
  final String? linkTarget;
  final List<CraftHtmlBox> children;

  const CraftHtmlBox({
    required this.style,
    this.text,
    this.linkTarget,
    this.children = const [],
  });

  bool get isText => text != null;

  String get textContent =>
      text ?? children.map((child) => child.textContent).join(' ');
}
