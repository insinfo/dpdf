import '../css/css_values.dart';
import '../model/html_box.dart';

/// Resolved content and edge dimensions for one CSS box under a constraint.
class HtmlBoxGeometry {
  final double paintX;
  final double paintWidth;
  final double x;
  final double contentWidth;
  final double marginTop;
  final double marginRight;
  final double marginBottom;
  final double marginLeft;
  final double paddingTop;
  final double paddingRight;
  final double paddingBottom;
  final double paddingLeft;

  const HtmlBoxGeometry({
    required this.paintX,
    required this.paintWidth,
    required this.x,
    required this.contentWidth,
    required this.marginTop,
    required this.marginRight,
    required this.marginBottom,
    required this.marginLeft,
    required this.paddingTop,
    required this.paddingRight,
    required this.paddingBottom,
    required this.paddingLeft,
  });

  factory HtmlBoxGeometry.resolve(
      HtmlBoxStyle style, double x, double availableWidth) {
    double edge(CssLength value) => value.resolve(availableWidth);
    final marginTop = edge(style.margin.top);
    final marginRight = edge(style.margin.right);
    final marginBottom = edge(style.margin.bottom);
    final marginLeft = edge(style.margin.left);
    final paddingTop = edge(style.padding.top);
    final paddingRight = edge(style.padding.right);
    final paddingBottom = edge(style.padding.bottom);
    final paddingLeft = edge(style.padding.left);
    final outerEdges = marginLeft + marginRight + paddingLeft + paddingRight;
    final naturalWidth =
        (availableWidth - outerEdges).clamp(0.0, availableWidth);
    final specifiedWidth =
        style.width.resolve(availableWidth, fallback: naturalWidth);
    final contentWidth = specifiedWidth.clamp(0.0, naturalWidth);
    return HtmlBoxGeometry(
      paintX: x + marginLeft,
      paintWidth: contentWidth + paddingLeft + paddingRight,
      x: x + marginLeft + paddingLeft,
      contentWidth: contentWidth,
      marginTop: marginTop,
      marginRight: marginRight,
      marginBottom: marginBottom,
      marginLeft: marginLeft,
      paddingTop: paddingTop,
      paddingRight: paddingRight,
      paddingBottom: paddingBottom,
      paddingLeft: paddingLeft,
    );
  }
}
