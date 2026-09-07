import 'package:dpdf/src/styledxmlparser/css/resolve/style_inheritance.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Determines whether an SVG attribute can be inherited.
class CraftSvgAttributeInheritance implements CraftStyleInheritance {
  /// Set of inheritable SVG style attributes in accordance with "https://www.w3.org/TR/SVG2/propidx.html".
  static final Set<String> _inheritableProperties = {
    CraftSvgConstants.Attributes.DIRECTION,
    CraftSvgConstants.Attributes.FILL,
    CraftSvgConstants.Attributes.FILL_OPACITY,
    CraftSvgConstants.Attributes.FILL_RULE,
    CraftSvgConstants.Attributes.MARKER,
    CraftSvgConstants.Attributes.MARKER_MID,
    CraftSvgConstants.Attributes.MARKER_END,
    CraftSvgConstants.Attributes.MARKER_START,
    CraftSvgConstants.Attributes.STROKE,
    CraftSvgConstants.Attributes.STROKE_DASHARRAY,
    CraftSvgConstants.Attributes.STROKE_DASHOFFSET,
    CraftSvgConstants.Attributes.STROKE_LINECAP,
    CraftSvgConstants.Attributes.STROKE_LINEJOIN,
    CraftSvgConstants.Attributes.STROKE_MITERLIMIT,
    CraftSvgConstants.Attributes.STROKE_OPACITY,
    CraftSvgConstants.Attributes.STROKE_WIDTH,
    CraftSvgConstants.Attributes.TEXT_ANCHOR,
    CraftSvgConstants.Attributes.CLIP_RULE,
  };

  @override
  bool isInheritable(String propertyIdentifier) {
    return _inheritableProperties.contains(propertyIdentifier);
  }
}
