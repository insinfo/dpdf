import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/marker_svg_node_renderer.dart';

/// Base dos elementos que só existem para conter outros (`<g>`, `<svg>`).
abstract class CraftAbstractBranchSvgNodeRenderer
    extends CraftAbstractSvgNodeRenderer implements CraftBranchSvgNodeRenderer {
  final List<CraftSvgNodeRenderer> _children = [];

  /// Os filhos são desenhados no próprio fluxo de conteúdo, cada um entre
  /// `q`/`Q`.
  ///
  /// O iText encapsula cada galho num Form XObject para poder recortar o
  /// viewport com a BBox. Aqui isso custaria caro sem entregar nada: o XObject
  /// exige um documento aberto (impedindo desenhar num canvas solto),
  /// esconde a geometria atrás de uma indireção e, no subconjunto suportado,
  /// só o `<svg>` estabelece viewport — e esse recorte é emitido
  /// explicitamente com `re W n`.
  @override
  Future<void> doDraw(CraftSvgDrawContext context) async {
    final canvas = context.getCurrentCanvas();
    for (final child in _children) {
      // Marcadores não se desenham na posição em que foram declarados; quem os
      // instancia é o elemento marcável, no vértice correspondente.
      if (child is CraftMarkerSvgNodeRenderer) continue;
      canvas.saveState();
      await child.draw(context);
      canvas.restoreState();
    }
  }

  @override
  void addChild(CraftSvgNodeRenderer child) {
    _children.add(child);
  }

  @override
  List<CraftSvgNodeRenderer> getChildren() {
    return List.unmodifiable(_children);
  }

  void deepCopyChildren(CraftAbstractBranchSvgNodeRenderer deepCopy) {
    for (var child in _children) {
      CraftSvgNodeRenderer newChild = child.createDeepCopy();
      newChild.setParent(deepCopy);
      deepCopy.addChild(newChild);
    }
  }

  @override
  CraftSvgNodeRenderer createDeepCopy();
}
