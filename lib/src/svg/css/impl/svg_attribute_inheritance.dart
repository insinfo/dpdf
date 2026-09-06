import 'package:dpdf/src/styledxmlparser/css/resolve/i_style_inheritance.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Helper class that allows you to check if a property is inheritable.
class SvgAttributeInheritance implements IStyleInheritance {
  /// Set of inheritable SVG style attributes in accordance with "https://www.w3.org/TR/SVG2/propidx.html".
  static final Set<String> _inheritableProperties = {
    SvgConstants.Attributes.DIRECTION,
    SvgConstants.Attributes.FILL,
    SvgConstants.Attributes.FILL_OPACITY,
    SvgConstants.Attributes.FILL_RULE,
    SvgConstants.Attributes.MARKER,
    SvgConstants.Attributes.MARKER_MID,
    SvgConstants.Attributes.MARKER_END,
    SvgConstants.Attributes.MARKER_START,
    SvgConstants.Attributes.STROKE,
    SvgConstants.Attributes.STROKE_DASHARRAY,
    SvgConstants.Attributes.STROKE_DASHOFFSET,
    SvgConstants.Attributes.STROKE_LINECAP,
    SvgConstants.Attributes.STROKE_LINEJOIN,
    SvgConstants.Attributes.STROKE_MITERLIMIT,
    SvgConstants.Attributes.STROKE_OPACITY,
    SvgConstants.Attributes.STROKE_WIDTH,
    SvgConstants.Attributes.TEXT_ANCHOR,
    SvgConstants.Attributes.CLIP_RULE,
  };

  @override
  bool isInheritable(String propertyIdentifier) {
    return _inheritableProperties.contains(propertyIdentifier);
  }
}
