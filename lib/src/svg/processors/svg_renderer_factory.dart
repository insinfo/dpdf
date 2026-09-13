import 'package:dpdf/src/svg/renderers/impl/circle_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/clip_path_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/ellipse_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/group_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/gradient_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/image_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/line_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/marker_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/mask_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/no_op_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/path_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/pattern_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/polygon_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/polyline_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/rectangle_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/svg_tag_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/switch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/symbol_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/text_path_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/use_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/text_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Associa nomes de elementos SVG aos renderizadores que os desenham.
///
/// Elementos fora do mapa devolvem `null` e são ignorados junto com a sua
/// subárvore. Isso é deliberado: desenhar parcialmente um elemento ainda não
/// implementado produziria um PDF errado em silêncio, enquanto omiti-lo deixa
/// a falta visível.
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
    SvgTags.TEXT_PATH: TextPathSvgNodeRenderer.new,
    SvgTags.SYMBOL: SymbolSvgNodeRenderer.new,
    SvgTags.SWITCH: SwitchSvgNodeRenderer.new,
    SvgTags.LINEAR_GRADIENT: LinearGradientSvgNodeRenderer.new,
    SvgTags.RADIAL_GRADIENT: RadialGradientSvgNodeRenderer.new,
    SvgTags.STOP: GradientStopSvgNodeRenderer.new,
    SvgTags.MARKER: MarkerSvgNodeRenderer.new,
    SvgTags.MASK: MaskSvgNodeRenderer.new,
    SvgTags.PATTERN: PatternSvgNodeRenderer.new,
    // Reconhecidos e explicitamente sem pintura própria.
    SvgTags.DEFS: NoOpSvgNodeRenderer.new,
    SvgTags.TITLE: NoOpSvgNodeRenderer.new,
    SvgTags.DESC: NoOpSvgNodeRenderer.new,
    SvgTags.METADATA: NoOpSvgNodeRenderer.new,
    SvgTags.STYLE: NoOpSvgNodeRenderer.new,
    // Conteúdo estrangeiro (tipicamente XHTML): reconhecido para que a sua
    // subárvore não seja confundida com SVG, e recusado de forma limpa em
    // vez de sair pela metade no fluxo de conteúdo.
    SvgTags.FOREIGN_OBJECT: NoOpSvgNodeRenderer.new,
    // Filtros exigem rasterização, que não tem equivalente no modelo de
    // imagem do PDF. A definição é reconhecida e nunca pinta; quem a
    // referencia por `filter=` continua sendo desenhado sem o efeito.
    SvgTags.FILTER: NoOpSvgNodeRenderer.new,
    SvgTags.FE_BLEND: NoOpSvgNodeRenderer.new,
    SvgTags.FE_COLOR_MATRIX: NoOpSvgNodeRenderer.new,
    SvgTags.FE_COMPONENT_TRANSFER: NoOpSvgNodeRenderer.new,
    SvgTags.FE_COMPOSITE: NoOpSvgNodeRenderer.new,
    SvgTags.FE_COMVOLVE_MATRIX: NoOpSvgNodeRenderer.new,
    SvgTags.FE_DIFFUSE_LIGHTING: NoOpSvgNodeRenderer.new,
    SvgTags.FE_DISPLACEMENT_MAP: NoOpSvgNodeRenderer.new,
    SvgTags.FE_DISTANT_LIGHT: NoOpSvgNodeRenderer.new,
    SvgTags.FE_FLOOD: NoOpSvgNodeRenderer.new,
    SvgTags.FE_FUNC_A: NoOpSvgNodeRenderer.new,
    SvgTags.FE_FUNC_B: NoOpSvgNodeRenderer.new,
    SvgTags.FE_FUNC_G: NoOpSvgNodeRenderer.new,
    SvgTags.FE_FUNC_R: NoOpSvgNodeRenderer.new,
    SvgTags.FE_GAUSSIAN_BLUR: NoOpSvgNodeRenderer.new,
    SvgTags.FE_IMAGE: NoOpSvgNodeRenderer.new,
    SvgTags.FE_MERGE: NoOpSvgNodeRenderer.new,
    SvgTags.FE_MERGE_NODE: NoOpSvgNodeRenderer.new,
    SvgTags.FE_MORPHOLOGY: NoOpSvgNodeRenderer.new,
    SvgTags.FE_OFFSET: NoOpSvgNodeRenderer.new,
    SvgTags.FE_POINT_LIGHT: NoOpSvgNodeRenderer.new,
    SvgTags.FE_SPECULAR_LIGHTING: NoOpSvgNodeRenderer.new,
    SvgTags.FE_SPOTLIGHT: NoOpSvgNodeRenderer.new,
    SvgTags.FE_TILE: NoOpSvgNodeRenderer.new,
    SvgTags.FE_TURBULENCE: NoOpSvgNodeRenderer.new,
    // Declarativos sem efeito numa saída estática: animação, script e
    // definições de fonte SVG.
    SvgTags.ANIMATE: NoOpSvgNodeRenderer.new,
    SvgTags.ANIMATE_COLOR: NoOpSvgNodeRenderer.new,
    SvgTags.ANIMATE_MOTION: NoOpSvgNodeRenderer.new,
    SvgTags.ANIMATE_TRANSFORM: NoOpSvgNodeRenderer.new,
    SvgTags.SET: NoOpSvgNodeRenderer.new,
    SvgTags.MPATH: NoOpSvgNodeRenderer.new,
    SvgTags.SCRIPT: NoOpSvgNodeRenderer.new,
    SvgTags.VIEW: NoOpSvgNodeRenderer.new,
    SvgTags.CURSOR: NoOpSvgNodeRenderer.new,
    SvgTags.COLOR_PROFILE: NoOpSvgNodeRenderer.new,
    SvgTags.FONT: NoOpSvgNodeRenderer.new,
    SvgTags.FONT_FACE: NoOpSvgNodeRenderer.new,
    SvgTags.FONT_FACE_FORMAT: NoOpSvgNodeRenderer.new,
    SvgTags.FONT_FACE_NAME: NoOpSvgNodeRenderer.new,
    SvgTags.FONT_FACE_SRC: NoOpSvgNodeRenderer.new,
    SvgTags.FONT_FACE_URI: NoOpSvgNodeRenderer.new,
  };

  /// Nomes de elementos preservam maiúsculas em SVG (`clipPath`), então a
  /// busca é feita pelo nome exato, sem normalizar caixa.
  static SvgNodeRenderer? create(String tagName) => _renderers[tagName]?.call();

  /// Se o elemento é conhecido, ainda que não pinte nada.
  static bool supports(String tagName) => _renderers.containsKey(tagName);
}
