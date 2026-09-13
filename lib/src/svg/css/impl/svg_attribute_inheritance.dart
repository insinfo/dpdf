import 'package:dpdf/src/styledxmlparser/css/resolve/style_inheritance.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Determines whether an SVG attribute can be inherited.
class SvgAttributeInheritance implements StyleInheritance {
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
    // SVG 1.1 §10.12 descreve `text-decoration` como propagada ao conteúdo
    // do elemento de texto; propagar por herança dá o mesmo resultado no
    // subconjunto suportado e evita um segundo mecanismo só para ela.
    SvgAttributes.TEXT_DECORATION,
    // `xml:space` é herdado pela própria definição de XML, e o tratamento de
    // espaços da SVG 1.1 §10.15 precisa dele já resolvido em cada folha.
    SvgAttributes.XML_SPACE,
  };

  @override
  bool isInheritable(String propertyIdentifier) {
    return _inheritableProperties.contains(propertyIdentifier);
  }
}
