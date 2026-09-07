import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_coordinate_utils.dart';
import 'package:dpdf/src/svg/utils/svg_css_utils.dart';

/// Base dos elementos que estabelecem um viewport próprio (`<svg>`).
///
/// Diferente de `<g>`, um contêiner recorta o que desenha e pode reescalar o
/// sistema de coordenadas através de `viewBox`.
abstract class CraftAbstractContainerSvgNodeRenderer
    extends CraftAbstractBranchSvgNodeRenderer {
  /// Abaixo desta tolerância um `viewBox` é tratado como degenerado; é a
  /// mesma ordem de grandeza usada pelo resto do kernel para comparar pontos.
  static const double _epsilon = 1e-6;

  @override
  bool canConstructViewPort() => true;

  @override
  bool canElementFill() => false;

  @override
  Future<void> doDraw(CraftSvgDrawContext context) async {
    context.addViewPort(calculateViewPort(context));
    // A ordem importa: o recorte vale no sistema de coordenadas do pai, então
    // é emitido antes de o `viewBox` reescalar o espaço para os filhos.
    _applyViewPortClip(context);
    _applyViewBox(context);
    await super.doDraw(context);
    context.removeCurrentViewPort();
  }

  /// Calcula o retângulo que este contêiner ocupa no espaço do pai.
  CraftRectangle calculateViewPort(CraftSvgDrawContext context) {
    final parent = getParent();
    if (parent is! CraftAbstractSvgNodeRenderer) {
      // Contêiner de topo (o pai é a raiz sintética): o viewport já foi
      // decidido por quem iniciou a conversão, e recalculá-lo resolveria os
      // percentuais duas vezes.
      return (context.getCurrentViewPort() ?? CraftRectangle(0, 0, 0, 0))
          .clone();
    }
    final percentBase = parent.getCurrentViewBox(context);
    final x = parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.X, '0'), context);
    final y = parseVerticalLength(
        getAttributeOrDefault(SvgAttributes.Y, '0'), context);
    final width = parseHorizontalLength(
        getAttributeOrDefault(
            SvgAttributes.WIDTH, SvgValues.DEFAULT_WIDTH_AND_HEIGHT_VALUE),
        context);
    final height = parseVerticalLength(
        getAttributeOrDefault(
            SvgAttributes.HEIGHT, SvgValues.DEFAULT_WIDTH_AND_HEIGHT_VALUE),
        context);
    return CraftRectangle(x, y, width <= 0 ? percentBase.getWidth() : width,
        height <= 0 ? percentBase.getHeight() : height);
  }

  void _applyViewPortClip(CraftSvgDrawContext context) {
    final viewPort = context.getCurrentViewPort();
    if (viewPort == null) return;
    context
        .getCurrentCanvas()
        .rectangle(viewPort.getX(), viewPort.getY(), viewPort.getWidth(),
            viewPort.getHeight())
        .clip();
  }

  /// Traduz `viewBox` na transformação que mapeia o sistema de coordenadas do
  /// usuário sobre o viewport, e ajusta o viewport corrente pelo inverso para
  /// que percentuais dos filhos continuem sendo resolvidos no espaço certo.
  void _applyViewBox(CraftSvgDrawContext context) {
    final viewPort = context.getCurrentViewPort();
    if (viewPort == null) return;
    final values = CraftSvgCssUtils.parseViewBox(this);
    if (values == null || values.length < SvgValues.VIEWBOX_VALUES_NUMBER) {
      return;
    }
    final viewBox = CraftRectangle(values[0], values[1], values[2], values[3]);
    if (viewBox.getWidth().abs() < _epsilon ||
        viewBox.getHeight().abs() < _epsilon) {
      // Largura ou altura zero desliga o elemento, conforme a especificação.
      context.getCurrentCanvas().concatMatrix(0, 0, 0, 0, 0, 0);
      return;
    }

    final aspectRatio = _retrieveAlignAndMeet();
    final applied = CraftSvgCoordinateUtils.applyViewBox(
        viewBox, viewPort, aspectRatio[0], aspectRatio[1]);
    final scaleX = applied.getWidth() / viewBox.getWidth();
    final scaleY = applied.getHeight() / viewBox.getHeight();
    final offsetX = applied.getX() / scaleX - viewBox.getX();
    final offsetY = applied.getY() / scaleY - viewBox.getY();

    final canvas = context.getCurrentCanvas();
    if (offsetX != 0 || offsetY != 0) {
      canvas.concatMatrix(1, 0, 0, 1, offsetX, offsetY);
      viewPort.setX(viewPort.getX() - offsetX);
      viewPort.setY(viewPort.getY() - offsetY);
    }
    if (scaleX != 1 || scaleY != 1) {
      canvas.concatMatrix(scaleX, 0, 0, scaleY, 0, 0);
      viewPort.setX(viewPort.getX() / scaleX);
      viewPort.setWidth(viewPort.getWidth() / scaleX);
      viewPort.setY(viewPort.getY() / scaleY);
      viewPort.setHeight(viewPort.getHeight() / scaleY);
    }
  }

  List<String> _retrieveAlignAndMeet() {
    final raw = getAttribute(SvgAttributes.PRESERVE_ASPECT_RATIO) ??
        getAttribute(SvgAttributes.PRESERVE_ASPECT_RATIO.toLowerCase());
    var align = SvgValues.DEFAULT_ASPECT_RATIO;
    var meetOrSlice = SvgValues.MEET;
    if (raw != null) {
      final parts = CraftSvgCssUtils.splitValueList(raw);
      // `defer` só faz sentido em <image> e é ignorado silenciosamente.
      final meaningful =
          parts.where((part) => part != SvgValues.DEFER).toList();
      if (meaningful.isNotEmpty) align = meaningful[0];
      if (meaningful.length > 1) meetOrSlice = meaningful[1];
    }
    return [align, meetOrSlice];
  }
}
