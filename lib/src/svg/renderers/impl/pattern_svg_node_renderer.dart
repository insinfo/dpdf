import 'dart:math' as math;

import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_resources.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_pattern_paint_server.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/transform_utils.dart';
import 'package:dpdf/src/svg/utils/template_resolve_utils.dart';
import 'package:dpdf/src/svg/utils/svg_css_utils.dart';

class PatternSvgNodeRenderer extends AbstractBranchSvgNodeRenderer
    implements SvgPatternPaintServer {
  @override
  Future<void> doDraw(SvgDrawContext context) async {}

  @override
  Future<bool> applyPattern(SvgDrawContext context, Rectangle bounds) async {
    final target = context.getCurrentCanvas();
    final document = target.getDocument();
    if (document == null || target.resources == null) return false;
    final id = getAttribute(SvgAttributes.ID) ?? '';
    if (id.isNotEmpty && !context.pushPatternId(id)) return false;
    try {
      TemplateResolveUtils.resolve(this, context);
      final objectUnits = (getAttribute(SvgAttributes.PATTERN_UNITS) ??
              SvgValues.OBJECT_BOUNDING_BOX) !=
          SvgValues.USER_SPACE_ON_USE;
      double coordinate(String name, String fallback, double origin,
          double size, bool horizontal) {
        final raw = getAttribute(name) ?? fallback;
        if (raw.trim().endsWith('%')) {
          final value =
              double.tryParse(raw.trim().substring(0, raw.trim().length - 1)) ??
                  0;
          return origin + size * value / 100;
        }
        if (objectUnits) {
          return origin + size * (double.tryParse(raw) ?? 0);
        }
        return horizontal
            ? parseHorizontalLength(raw, context)
            : parseVerticalLength(raw, context);
      }

      final x = coordinate(
          SvgAttributes.X, '0', bounds.getX(), bounds.getWidth(), true);
      final y = coordinate(
          SvgAttributes.Y, '0', bounds.getY(), bounds.getHeight(), false);
      final width =
          coordinate(SvgAttributes.WIDTH, '0', 0, bounds.getWidth(), true)
              .abs();
      final height =
          coordinate(SvgAttributes.HEIGHT, '0', 0, bounds.getHeight(), false)
              .abs();
      if (width <= 1e-9 || height <= 1e-9) return false;

      final resources = PdfResources(PdfDictionary());
      final stream = PdfStream()
        ..put(PdfName.type, PdfName.pattern)
        ..put(PdfName('PatternType'), PdfNumber.fromInt(1))
        ..put(PdfName('PaintType'), PdfNumber.fromInt(1))
        ..put(PdfName('TilingType'), PdfNumber.fromInt(1))
        ..put(PdfName.bBox, PdfArray.fromDoubles([0, 0, width, height]))
        ..put(PdfName('XStep'), PdfNumber(width))
        ..put(PdfName('YStep'), PdfNumber(height))
        ..put(PdfName.resources, resources.pdfRepresentation());
      stream.attachToDocument(document);

      var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = x, f = y;
      final transformRaw = getAttribute(SvgAttributes.PATTERN_TRANSFORM);
      if (transformRaw != null && transformRaw.trim().isNotEmpty) {
        final transform = TransformUtils.parseTransform(transformRaw);
        a = transform.m00;
        b = transform.m10;
        c = transform.m01;
        d = transform.m11;
        e += transform.m02;
        f += transform.m12;
      }
      stream.put(PdfName.matrix, PdfArray.fromDoubles([a, b, c, d, e, f]));

      final patternCanvas = PdfCanvas(stream, resources, document);
      context.pushCanvas(patternCanvas);
      context.addViewPort(Rectangle(0, 0, width, height));
      try {
        final viewBox = SvgCssUtils.parseViewBox(this);
        if (viewBox != null &&
            viewBox.length >= 4 &&
            viewBox[2] > 0 &&
            viewBox[3] > 0) {
          _applyViewBox(patternCanvas, viewBox, width, height);
        } else if ((getAttribute(SvgAttributes.PATTERN_CONTENT_UNITS) ??
                SvgValues.USER_SPACE_ON_USE) ==
            SvgValues.OBJECT_BOUNDING_BOX) {
          patternCanvas.concatMatrix(
              bounds.getWidth(), 0, 0, bounds.getHeight(), 0, 0);
        }
        for (final child in getChildren()) {
          patternCanvas.saveState();
          await child.draw(context);
          patternCanvas.restoreState();
        }
      } finally {
        context.removeCurrentViewPort();
        context.popCanvas();
      }
      await target.setFillPattern(stream);
      return true;
    } finally {
      if (id.isNotEmpty) context.popPatternId();
    }
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  void _applyViewBox(
      PdfCanvas canvas, List<double> viewBox, double width, double height) {
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
    final offsetX = align.startsWith('xmax')
        ? spareX
        : align.startsWith('xmid')
            ? spareX / 2
            : 0.0;
    final offsetY = align.endsWith('ymax')
        ? spareY
        : align.endsWith('ymid')
            ? spareY / 2
            : 0.0;
    canvas.concatMatrix(1, 0, 0, 1, offsetX, offsetY);
    canvas.concatMatrix(scaleX, 0, 0, scaleY, 0, 0);
    canvas.concatMatrix(1, 0, 0, 1, -viewBox[0], -viewBox[1]);
  }

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = PatternSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}
