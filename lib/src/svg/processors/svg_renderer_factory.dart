import 'package:dpdf/src/svg/renderers/impl/circle_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/ellipse_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/group_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/line_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/no_op_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/path_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/polygon_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/polyline_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/rectangle_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/svg_tag_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Associa nomes de elementos SVG aos renderizadores que os desenham.
///
/// Elementos fora do mapa devolvem `null` e são ignorados junto com a sua
/// subárvore. Isso é deliberado: desenhar parcialmente um `<use>` ou um
/// `<text>` ainda não implementado produziria um PDF errado em silêncio,
/// enquanto omiti-lo deixa a falta visível.
class CraftSvgRendererFactory {
  CraftSvgRendererFactory._();

  static final Map<String, CraftSvgNodeRenderer Function()> _renderers = {
    SvgTags.SVG: CraftSvgTagSvgNodeRenderer.new,
    SvgTags.G: CraftGroupSvgNodeRenderer.new,
    // `<a>` é um contêiner: o hyperlink não é representável no fluxo de
    // conteúdo, mas o que está dentro dele continua sendo desenhado.
    SvgTags.A: CraftGroupSvgNodeRenderer.new,
    SvgTags.RECT: CraftRectangleSvgNodeRenderer.new,
    SvgTags.CIRCLE: CraftCircleSvgNodeRenderer.new,
    SvgTags.ELLIPSE: CraftEllipseSvgNodeRenderer.new,
    SvgTags.LINE: CraftLineSvgNodeRenderer.new,
    SvgTags.POLYLINE: CraftPolylineSvgNodeRenderer.new,
    SvgTags.POLYGON: CraftPolygonSvgNodeRenderer.new,
    SvgTags.PATH: CraftPathSvgNodeRenderer.new,
    // Reconhecidos e explicitamente sem pintura própria.
    SvgTags.DEFS: CraftNoOpSvgNodeRenderer.new,
    SvgTags.TITLE: CraftNoOpSvgNodeRenderer.new,
    SvgTags.DESC: CraftNoOpSvgNodeRenderer.new,
    SvgTags.METADATA: CraftNoOpSvgNodeRenderer.new,
    SvgTags.STYLE: CraftNoOpSvgNodeRenderer.new,
  };

  /// Nomes de elementos preservam maiúsculas em SVG (`clipPath`), então a
  /// busca é feita pelo nome exato, sem normalizar caixa.
  static CraftSvgNodeRenderer? create(String tagName) =>
      _renderers[tagName]?.call();

  /// Se o elemento é conhecido, ainda que não pinte nada.
  static bool supports(String tagName) => _renderers.containsKey(tagName);
}
