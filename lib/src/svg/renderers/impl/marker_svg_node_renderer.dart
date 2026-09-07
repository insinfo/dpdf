import 'dart:math' as math;

import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/svg/marker_vertex_type.dart';
import 'package:dpdf/src/svg/renderers/marker_capable.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_container_svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_css_utils.dart';

class MarkerSvgNodeRenderer extends AbstractContainerSvgNodeRenderer {
  @override
  Future<void> doDraw(SvgDrawContext context) async {}

  Future<void> drawAt(SvgDrawContext context, SvgMarkerVertex vertex,
      MarkerVertexType type, double strokeWidth) async {
    final canvas = context.getCurrentCanvas();
    final width = parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.MARKER_WIDTH, '3'), context);
    final height = parseVerticalLength(
        getAttributeOrDefault(SvgAttributes.MARKER_HEIGHT, '3'), context);
    if (width <= 0 || height <= 0) return;
    final refX = parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.REFX, '0'), context);
    final refY = parseVerticalLength(
        getAttributeOrDefault(SvgAttributes.REFY, '0'), context);
    final orient = getAttribute(SvgAttributes.ORIENT) ?? '0';
    var angle = 0.0;
    if (orient == SvgValues.AUTO || orient == SvgValues.AUTO_START_REVERSE) {
      angle = type == MarkerVertexType.MARKER_MID
          ? vertex.middleAngle
          : type == MarkerVertexType.MARKER_START
              ? vertex.outgoingAngle
              : vertex.incomingAngle;
      if (orient == SvgValues.AUTO_START_REVERSE &&
          type == MarkerVertexType.MARKER_START) {
        angle += math.pi;
      }
    } else {
      angle = (double.tryParse(orient.replaceAll('deg', '').trim()) ?? 0) *
          math.pi /
          180;
    }

    canvas.saveState();
    try {
      canvas.concatMatrix(1, 0, 0, 1, vertex.x, vertex.y);
      if (angle != 0) {
        canvas.concatMatrix(math.cos(angle), math.sin(angle), -math.sin(angle),
            math.cos(angle), 0, 0);
      }
      if ((getAttribute(SvgAttributes.MARKER_UNITS) ?? SvgValues.STROKEWIDTH) ==
          SvgValues.STROKEWIDTH) {
        final userUnit = parseHorizontalLength('1', context);
        final scale = userUnit == 0 ? 1.0 : strokeWidth / userUnit;
        canvas.concatMatrix(scale, 0, 0, scale, 0, 0);
      }
      final viewBox = SvgCssUtils.parseViewBox(this);
      if (viewBox != null &&
          viewBox.length >= 4 &&
          viewBox[2] != 0 &&
          viewBox[3] != 0) {
        var scaleX = width / viewBox[2];
        var scaleY = height / viewBox[3];
        final aspect = getAttribute(SvgAttributes.PRESERVE_ASPECT_RATIO) ??
            SvgValues.DEFAULT_ASPECT_RATIO;
        final parts = SvgCssUtils.splitValueList(aspect)
            .where((part) => part.toLowerCase() != SvgValues.DEFER)
            .toList();
        final align = parts.isEmpty
            ? SvgValues.DEFAULT_ASPECT_RATIO.toLowerCase()
            : parts.first.toLowerCase();
        final meetOrSlice = parts.length > 1 ? parts[1].toLowerCase() : '';
        if (align != SvgValues.NONE.toLowerCase()) {
          final uniform = meetOrSlice == SvgValues.SLICE
              ? math.max(scaleX, scaleY)
              : math.min(scaleX, scaleY);
          scaleX = scaleY = uniform;
        }
        final spareX = width - viewBox[2] * scaleX;
        final spareY = height - viewBox[3] * scaleY;
        final offsetX = _alignmentOffset(align, spareX, horizontal: true);
        final offsetY = _alignmentOffset(align, spareY, horizontal: false);
        final mappedRefX = offsetX + (refX - viewBox[0]) * scaleX;
        final mappedRefY = offsetY + (refY - viewBox[1]) * scaleY;
        canvas.concatMatrix(1, 0, 0, 1, -mappedRefX, -mappedRefY);
        _clipViewport(canvas, width, height);
        canvas.concatMatrix(1, 0, 0, 1, offsetX, offsetY);
        canvas.concatMatrix(scaleX, 0, 0, scaleY, 0, 0);
        canvas.concatMatrix(1, 0, 0, 1, -viewBox[0], -viewBox[1]);
      } else {
        canvas.concatMatrix(1, 0, 0, 1, -refX, -refY);
        _clipViewport(canvas, width, height);
      }
      for (final child in getChildren()) {
        canvas.saveState();
        await child.draw(context);
        canvas.restoreState();
      }
    } finally {
      canvas.restoreState();
    }
  }

  double _alignmentOffset(String align, double spare,
      {required bool horizontal}) {
    if (align == SvgValues.NONE.toLowerCase()) return 0;
    if (horizontal) {
      if (align.startsWith('xmax')) return spare;
      if (align.startsWith('xmid')) return spare / 2;
    } else {
      if (align.endsWith('ymax')) return spare;
      if (align.endsWith('ymid')) return spare / 2;
    }
    return 0;
  }

  void _clipViewport(PdfCanvas canvas, double width, double height) {
    final overflow = (getAttribute('overflow') ?? 'hidden').toLowerCase();
    if (overflow == 'visible') return;
    canvas.rectangle(0.0, 0.0, width, height).clip();
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = MarkerSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}
