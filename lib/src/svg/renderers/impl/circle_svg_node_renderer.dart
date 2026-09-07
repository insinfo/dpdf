import 'package:dpdf/src/svg/renderers/impl/ellipse_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Renderizador de `<circle>`: uma elipse cujos dois raios vêm de `r`.
class CraftCircleSvgNodeRenderer extends CraftEllipseSvgNodeRenderer {
  @override
  bool setParameters(CraftSvgDrawContext context) {
    initCenter(context);
    final radius = getAttribute(SvgAttributes.R);
    if (radius == null) return false;
    // O raio de um círculo é medido na diagonal normalizada, mas para o
    // subconjunto suportado (sem percentuais) o eixo horizontal basta.
    rx = parseHorizontalLength(radius, context);
    ry = rx;
    return rx > 0;
  }

  @override
  CraftSvgNodeRenderer createDeepCopy() {
    final copy = CraftCircleSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
