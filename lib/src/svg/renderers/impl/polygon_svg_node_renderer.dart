import 'package:dpdf/src/svg/renderers/impl/polyline_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';

/// Renderizador de `<polygon>`: uma polilinha com o contorno fechado.
class CraftPolygonSvgNodeRenderer extends CraftPolylineSvgNodeRenderer {
  @override
  bool get closesPath => true;

  @override
  CraftSvgNodeRenderer createDeepCopy() {
    final copy = CraftPolygonSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
