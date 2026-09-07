import 'package:dpdf/src/styledxmlparser/css/resolve/style_inheritance.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Determines whether an SVG attribute can be inherited.
class CraftSvgAttributeInheritance implements CraftStyleInheritance {
  /// Set of inheritable SVG style attributes in accordance with "https://www.w3.org/TR/SVG2/propidx.html".
  static final Set<String> _inheritableProperties = {
    SvgAttributes.DIRECTION,
    SvgAttributes.FILL,
    SvgAttributes.FILL_OPACITY,
    SvgAttributes.FILL_RULE,
    SvgAttributes.MARKER,
    SvgAttributes.MARKER_MID,
    SvgAttributes.MARKER_END,
    SvgAttributes.MARKER_START,
    SvgAttributes.STROKE,
    SvgAttributes.STROKE_DASHARRAY,
    SvgAttributes.STROKE_DASHOFFSET,
    SvgAttributes.STROKE_LINECAP,
    SvgAttributes.STROKE_LINEJOIN,
    SvgAttributes.STROKE_MITERLIMIT,
    SvgAttributes.STROKE_OPACITY,
    SvgAttributes.STROKE_WIDTH,
    SvgAttributes.TEXT_ANCHOR,
    SvgAttributes.CLIP_RULE,
  };

  @override
  bool isInheritable(String propertyIdentifier) {
    return _inheritableProperties.contains(propertyIdentifier);
  }
}
