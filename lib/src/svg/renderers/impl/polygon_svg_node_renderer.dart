import 'package:dpdf/src/svg/renderers/impl/polyline_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';

/// Renderizador de `<polygon>`: uma polilinha com o contorno fechado.
class PolygonSvgNodeRenderer extends PolylineSvgNodeRenderer {
  @override
  bool get closesPath => true;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = PolygonSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
