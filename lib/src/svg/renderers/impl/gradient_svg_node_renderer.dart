import 'dart:math' as math;

import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_shading.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_shading_paint_server.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_color_utils.dart';
import 'package:dpdf/src/svg/utils/transform_utils.dart';
import 'package:dpdf/src/svg/utils/template_resolve_utils.dart';

class GradientStopSvgNodeRenderer extends AbstractSvgNodeRenderer {
  @override
  bool canElementFill() => false;
  @override
  Future<void> doDraw(SvgDrawContext context) async {}
  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;
  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = GradientStopSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}

abstract class GradientSvgNodeRenderer extends AbstractBranchSvgNodeRenderer
    implements SvgShadingPaintServer {
  @override
  Future<void> doDraw(SvgDrawContext context) async {}

  ({List<double> offsets, List<List<double>> colors}) stops() {
    final values = <({double offset, List<double> color})>[];
    for (final child in getChildren()) {
      if (child is! GradientStopSvgNodeRenderer) continue;
      final raw = child.getAttribute(SvgAttributes.OFFSET) ?? '0';
      var offset = raw.trim().endsWith('%')
          ? (double.tryParse(raw.trim().substring(0, raw.trim().length - 1)) ??
                  0) /
              100
          : double.tryParse(raw) ?? 0;
      offset = offset.clamp(0, 1).toDouble();
      if (values.isNotEmpty) offset = math.max(offset, values.last.offset);
      final color =
          SvgColorUtils.parse(child.getAttribute(SvgTags.STOP_COLOR) ?? 'black')
              ?.getColorValue();
      values.add((offset: offset, color: color ?? <double>[0, 0, 0]));
    }
    if (values.isEmpty) {
      values.addAll([
        (offset: 0, color: <double>[0, 0, 0]),
        (offset: 1, color: <double>[0, 0, 0]),
      ]);
    } else if (values.length == 1) {
      values.add((offset: 1, color: List<double>.from(values.first.color)));
    }
    if (values.first.offset > 0) {
      values
          .insert(0, (offset: 0, color: List<double>.from(values.first.color)));
    }
    if (values.last.offset < 1) {
      values.add((offset: 1, color: List<double>.from(values.last.color)));
    }
    return (
      offsets: values.map((v) => v.offset).toList(),
      colors: values.map((v) => v.color).toList(),
    );
  }

  double coordinate(String name, String fallback, double origin, double size,
      SvgDrawContext context) {
    final raw = getAttribute(name) ?? fallback;
    if (raw.trim().endsWith('%')) {
      final value =
          double.tryParse(raw.trim().substring(0, raw.trim().length - 1)) ?? 0;
      return origin + size * value / 100;
    }
    final userSpace = getAttribute(SvgAttributes.GRADIENT_UNITS) ==
        SvgValues.USER_SPACE_ON_USE;
    if (!userSpace) {
      final value = double.tryParse(raw.trim());
      if (value != null) return origin + size * value;
    }
    return name == SvgAttributes.Y1 ||
            name == SvgAttributes.Y2 ||
            name == SvgAttributes.CY ||
            name == 'fy'
        ? parseVerticalLength(raw, context)
        : parseHorizontalLength(raw, context);
  }

  Future<void> paintTransformed(
      SvgDrawContext context, Future<void> Function() paint) async {
    final raw = getAttribute(SvgAttributes.GRADIENT_TRANSFORM);
    if (raw == null || raw.trim().isEmpty) {
      await paint();
      return;
    }
    final transform = TransformUtils.parseTransform(raw);
    final canvas = context.getCurrentCanvas();
    canvas.saveState();
    try {
      if (!transform.isIdentity) {
        canvas.concatMatrix(transform.m00, transform.m10, transform.m01,
            transform.m11, transform.m02, transform.m12);
      }
      await paint();
    } finally {
      canvas.restoreState();
    }
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;
}

class LinearGradientSvgNodeRenderer extends GradientSvgNodeRenderer {
  @override
  Future<void> paintShading(SvgDrawContext context, Rectangle b) async {
    TemplateResolveUtils.resolve(this, context);
    final s = stops();
    await paintTransformed(
        context,
        () => context.getCurrentCanvas().shading(PdfShading.axialRgbStops(
              coordinate(
                  SvgAttributes.X1, '0%', b.getX(), b.getWidth(), context),
              coordinate(
                  SvgAttributes.Y1, '0%', b.getY(), b.getHeight(), context),
              coordinate(
                  SvgAttributes.X2, '100%', b.getX(), b.getWidth(), context),
              coordinate(
                  SvgAttributes.Y2, '0%', b.getY(), b.getHeight(), context),
              s.offsets,
              s.colors,
            )));
  }

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = LinearGradientSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}

class RadialGradientSvgNodeRenderer extends GradientSvgNodeRenderer {
  @override
  Future<void> paintShading(SvgDrawContext context, Rectangle b) async {
    TemplateResolveUtils.resolve(this, context);
    final s = stops();
    final cx =
        coordinate(SvgAttributes.CX, '50%', b.getX(), b.getWidth(), context);
    final cy =
        coordinate(SvgAttributes.CY, '50%', b.getY(), b.getHeight(), context);
    final fx = coordinate('fx', '50%', b.getX(), b.getWidth(), context);
    final fy = coordinate('fy', '50%', b.getY(), b.getHeight(), context);
    final r = coordinate(SvgAttributes.R, '50%', 0,
        math.max(b.getWidth(), b.getHeight()), context);
    await paintTransformed(
        context,
        () => context.getCurrentCanvas().shading(PdfShading.radialRgbStops(
            fx, fy, 0, cx, cy, r, s.offsets, s.colors)));
  }

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = RadialGradientSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}
