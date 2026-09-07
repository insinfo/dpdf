import 'package:dpdf/src/svg/renderers/impl/circle_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/clip_path_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/ellipse_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/group_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/gradient_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/image_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/line_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/no_op_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/path_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/polygon_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/polyline_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/rectangle_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/svg_tag_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/use_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/text_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Associa nomes de elementos SVG aos renderizadores que os desenham.
///
/// Elementos fora do mapa devolvem `null` e são ignorados junto com a sua
/// subárvore. Isso é deliberado: desenhar parcialmente um `<use>` ou um
/// `<text>` ainda não implementado produziria um PDF errado em silêncio,
/// enquanto omiti-lo deixa a falta visível.
class SvgRendererFactory {
  SvgRendererFactory._();

  static final Map<String, SvgNodeRenderer Function()> _renderers = {
    SvgTags.SVG: SvgTagSvgNodeRenderer.new,
    SvgTags.G: GroupSvgNodeRenderer.new,
    // `<a>` é um contêiner: o hyperlink não é representável no fluxo de
    // conteúdo, mas o que está dentro dele continua sendo desenhado.
    SvgTags.A: GroupSvgNodeRenderer.new,
    SvgTags.RECT: RectangleSvgNodeRenderer.new,
    SvgTags.CIRCLE: CircleSvgNodeRenderer.new,
    SvgTags.ELLIPSE: EllipseSvgNodeRenderer.new,
    SvgTags.LINE: LineSvgNodeRenderer.new,
    SvgTags.POLYLINE: PolylineSvgNodeRenderer.new,
    SvgTags.POLYGON: PolygonSvgNodeRenderer.new,
    SvgTags.PATH: PathSvgNodeRenderer.new,
    SvgTags.IMAGE: ImageSvgNodeRenderer.new,
    SvgTags.CLIP_PATH: ClipPathSvgNodeRenderer.new,
    SvgTags.USE: UseSvgNodeRenderer.new,
    SvgTags.TEXT: () => TextSvgNodeRenderer(root: true),
    SvgTags.TSPAN: TextSvgNodeRenderer.new,
    SvgTags.LINEAR_GRADIENT: LinearGradientSvgNodeRenderer.new,
    SvgTags.RADIAL_GRADIENT: RadialGradientSvgNodeRenderer.new,
    SvgTags.STOP: GradientStopSvgNodeRenderer.new,
    // Reconhecidos e explicitamente sem pintura própria.
    SvgTags.DEFS: NoOpSvgNodeRenderer.new,
    SvgTags.TITLE: NoOpSvgNodeRenderer.new,
    SvgTags.DESC: NoOpSvgNodeRenderer.new,
    SvgTags.METADATA: NoOpSvgNodeRenderer.new,
    SvgTags.STYLE: NoOpSvgNodeRenderer.new,
  };

  /// Nomes de elementos preservam maiúsculas em SVG (`clipPath`), então a
  /// busca é feita pelo nome exato, sem normalizar caixa.
  static SvgNodeRenderer? create(String tagName) => _renderers[tagName]?.call();

  /// Se o elemento é conhecido, ainda que não pinte nada.
  static bool supports(String tagName) => _renderers.containsKey(tagName);
}
