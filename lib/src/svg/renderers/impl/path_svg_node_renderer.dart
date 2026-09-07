import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/path/svg_path_parser.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Renderizador de `<path>`.
class CraftPathSvgNodeRenderer extends CraftAbstractSvgNodeRenderer {
  /// O `d` não admite unidades nem percentuais, só números em unidades de
  /// usuário. Ainda assim a escala é obtida do próprio contexto, medindo
  /// quanto vale uma unidade, para acompanhar a mesma conversão px→pt que os
  /// demais atributos sofrem.
  List<CraftSvgPathSegment> _segments(CraftSvgDrawContext context) {
    return CraftSvgPathParser.parse(getAttribute(SvgAttributes.D),
        unitScale: parseHorizontalLength('1', context));
  }

  @override
  Future<void> doDraw(CraftSvgDrawContext context) async {
    final canvas = context.getCurrentCanvas();
    for (final segment in _segments(context)) {
      final c = segment.coordinates;
      switch (segment.op) {
        case CraftSvgPathOp.moveTo:
          canvas.moveTo(c[0], c[1]);
          break;
        case CraftSvgPathOp.lineTo:
          canvas.lineTo(c[0], c[1]);
          break;
        case CraftSvgPathOp.curveTo:
          canvas.curveTo(c[0], c[1], c[2], c[3], c[4], c[5]);
          break;
        case CraftSvgPathOp.close:
          canvas.closePath();
          break;
      }
    }
  }

  /// Caixa envolvente dos pontos de controle: é um limite superior da caixa
  /// real da curva, suficiente para o uso a que serve (posicionar servidores
  /// de pintura) e sem o custo de resolver as raízes de cada Bézier.
  @override
  CraftRectangle? getObjectBoundingBox(CraftSvgDrawContext context) {
    double? minX, minY, maxX, maxY;
    for (final segment in _segments(context)) {
      for (var i = 0; i + 1 < segment.coordinates.length; i += 2) {
        final x = segment.coordinates[i];
        final y = segment.coordinates[i + 1];
        minX = minX == null || x < minX ? x : minX;
        maxX = maxX == null || x > maxX ? x : maxX;
        minY = minY == null || y < minY ? y : minY;
        maxY = maxY == null || y > maxY ? y : maxY;
      }
    }
    if (minX == null) return null;
    return CraftRectangle(minX, minY!, maxX! - minX, maxY! - minY);
  }

  @override
  CraftSvgNodeRenderer createDeepCopy() {
    final copy = CraftPathSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
