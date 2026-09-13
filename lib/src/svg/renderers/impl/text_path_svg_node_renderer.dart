import 'dart:math' as math;

import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_types_validation_utils.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/path_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_text_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_path_geometry.dart';
import 'package:dpdf/src/svg/utils/svg_text_layout.dart';

/// Renderizador de `<textPath>` (SVG 1.1 §10.13).
///
/// O conteúdo é montado primeiro numa linha reta, como se fosse um `<text>`
/// comum, e só então cada caractere é transportado para o caminho
/// referenciado: a distância percorrida até o meio do avanço do glifo decide
/// o ponto, e a tangente ali decide a rotação. Caracteres cuja posição cai
/// fora do caminho não são desenhados, como manda a §10.13.2.
class TextPathSvgNodeRenderer extends AbstractBranchSvgNodeRenderer
    implements SvgTextNodeRenderer, SvgTextLayoutNode {
  @override
  bool canElementFill() => false;

  /// Fora de um `<text>` o elemento não tem posição definida, e o percurso
  /// normal de desenho nunca deve alcançá-lo.
  @override
  Future<void> draw(SvgDrawContext context) async {}

  @override
  Future<void> doDraw(SvgDrawContext context) async {}

  @override
  Future<void> layoutText(SvgTextLayout layout, SvgDrawContext context) async {
    if (isHidden()) return;
    final path = _resolvePath(context);
    if (path == null || path.isEmpty) return;

    // A montagem interna começa na origem: `x` mede distância percorrida ao
    // longo do caminho e `y` mede o afastamento perpendicular dele.
    final straight = SvgTextLayout();
    for (final child in getChildren()) {
      if (child is SvgTextLayoutNode) {
        await (child as SvgTextLayoutNode).layoutText(straight, context);
      }
    }
    if (straight.runs.isEmpty) return;

    var advance = 0.0;
    for (final run in straight.runs) {
      if (run.x + run.width > advance) advance = run.x + run.width;
    }
    final start = _startOffset(context, path.length) + _anchorShift(advance);

    layout.startChunk();
    final chunk = layout.chunk;
    for (final run in straight.runs) {
      var cursor = run.x;
      for (final rune in run.text.runes) {
        final char = String.fromCharCode(rune);
        final width =
            run.font.getWidthPoint(char, run.fontSize) + run.letterSpacing;
        final point = path.pointAt(start + cursor + width / 2);
        cursor += width;
        if (point == null) continue;
        final cos = math.cos(point.angle);
        final sin = math.sin(point.angle);
        // Recua meio avanço pela tangente para levar o meio do glifo ao ponto
        // encontrado, e desloca pela normal o que `dy` pediu.
        layout.runs.add(SvgTextRun(
          leaf: run.leaf,
          text: char,
          font: run.font,
          fontSize: run.fontSize,
          letterSpacing: run.letterSpacing,
          x: point.x - cos * width / 2 - sin * run.y,
          y: point.y - sin * width / 2 + cos * run.y,
          rotation: point.angle,
          width: width,
          chunk: chunk,
          anchored: true,
        ));
      }
    }
  }

  /// §10.13.1: um comprimento, ou uma porcentagem do comprimento do caminho.
  double _startOffset(SvgDrawContext context, double pathLength) {
    final raw = getAttribute(SvgAttributes.START_OFFSET);
    if (raw == null || raw.trim().isEmpty) return 0;
    if (CssTypesValidationUtils.isPercentageValue(raw)) {
      final value = double.tryParse(raw.trim().replaceAll('%', ''));
      return value == null ? 0 : pathLength * value / 100.0;
    }
    return parseHorizontalLength(raw, context);
  }

  double _anchorShift(double advance) {
    final anchor = getAttributeOrDefault(
            SvgAttributes.TEXT_ANCHOR, SvgValues.TEXT_ANCHOR_START)
        .trim()
        .toLowerCase();
    if (anchor == SvgValues.TEXT_ANCHOR_MIDDLE) return -advance / 2;
    if (anchor == SvgValues.TEXT_ANCHOR_END) return -advance;
    return 0;
  }

  SvgFlattenedPath? _resolvePath(SvgDrawContext context) {
    final href = getAttribute(SvgAttributes.HREF) ??
        getAttribute(SvgAttributes.XLINK_HREF);
    if (href == null || !href.trim().startsWith('#')) return null;
    final target = context.getNamedObject(href.trim().substring(1));
    if (target is! PathSvgNodeRenderer) return null;
    return SvgFlattenedPath.fromSegments(target.pathSegments(context));
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = TextPathSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}
