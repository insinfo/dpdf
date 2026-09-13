import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_container_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';

/// Renderizador de `<symbol>` (SVG 1.1 §5.5).
///
/// O elemento nunca é desenhado onde foi declarado: só uma instância criada
/// por `<use>` chega ao fluxo de conteúdo. A cópia instanciada se comporta
/// como o `<svg>` gerado que a especificação descreve, ou seja estabelece
/// viewport próprio, recorta o excedente e honra `viewBox` e
/// `preserveAspectRatio`.
class SymbolSvgNodeRenderer extends AbstractContainerSvgNodeRenderer {
  bool _instantiated = false;

  /// Se esta cópia foi criada por um `<use>` e portanto deve desenhar.
  bool get isInstantiated => _instantiated;

  /// Marca a cópia como instanciada por `<use>`.
  void markInstantiated() {
    _instantiated = true;
  }

  @override
  Future<void> draw(SvgDrawContext context) async {
    if (!_instantiated) return;
    await super.draw(context);
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = SymbolSvgNodeRenderer();
    if (_instantiated) copy.markInstantiated();
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}
