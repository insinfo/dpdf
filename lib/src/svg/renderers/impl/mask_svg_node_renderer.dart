import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/extgstate/pdf_ext_g_state.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/xobject/pdf_form_x_object.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_mask_paint_server.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/template_resolve_utils.dart';

/// Emits an SVG `<mask>` as a PDF transparency-group soft mask.
class MaskSvgNodeRenderer extends AbstractBranchSvgNodeRenderer
    implements SvgMaskPaintServer {
  @override
  Future<void> doDraw(SvgDrawContext context) async {}

  @override
  Future<bool> applyMask(SvgDrawContext context, Rectangle bounds) async {
    final target = context.getCurrentCanvas();
    final document = target.getDocument();
    if (document == null || target.resources == null) return false;
    final id = getAttribute(SvgAttributes.ID) ?? '';
    if (id.isNotEmpty && !context.pushMaskId(id)) return false;
    try {
      TemplateResolveUtils.resolve(this, context);
      final objectUnits = (getAttribute(SvgAttributes.MASK_UNITS) ??
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
        if (objectUnits) return origin + size * (double.tryParse(raw) ?? 0);
        return horizontal
            ? parseHorizontalLength(raw, context)
            : parseVerticalLength(raw, context);
      }

      final x = coordinate(
          SvgAttributes.X, '-10%', bounds.getX(), bounds.getWidth(), true);
      final y = coordinate(
          SvgAttributes.Y, '-10%', bounds.getY(), bounds.getHeight(), false);
      final width =
          coordinate(SvgAttributes.WIDTH, '120%', 0, bounds.getWidth(), true)
              .abs();
      final height =
          coordinate(SvgAttributes.HEIGHT, '120%', 0, bounds.getHeight(), false)
              .abs();
      if (width <= 1e-9 || height <= 1e-9) return false;

      final form = PdfFormXObject(Rectangle(x, y, width, height));
      form.pdfRepresentation().put(
          PdfName('Group'),
          PdfDictionary()
            ..put(PdfName.s, PdfName('Transparency'))
            ..put(PdfName('CS'), PdfName.deviceRgb));
      form.pdfRepresentation().attachToDocument(document);
      final maskCanvas = await PdfCanvas.fromFormXObject(form, document);
      context.pushCanvas(maskCanvas);
      context.addViewPort(Rectangle(x, y, width, height));
      try {
        if ((getAttribute(SvgAttributes.MASK_CONTENT_UNITS) ??
                SvgValues.USER_SPACE_ON_USE) ==
            SvgValues.OBJECT_BOUNDING_BOX) {
          maskCanvas.concatMatrix(bounds.getWidth(), 0, 0, bounds.getHeight(),
              bounds.getX(), bounds.getY());
        }
        for (final child in getChildren()) {
          maskCanvas.saveState();
          await child.draw(context);
          maskCanvas.restoreState();
        }
      } finally {
        context.removeCurrentViewPort();
        context.popCanvas();
      }

      final mode = (getAttribute(SvgAttributes.MASK_TYPE) ?? 'luminance')
                  .toLowerCase() ==
              'alpha'
          ? PdfName('Alpha')
          : PdfName('Luminosity');
      final softMask = PdfDictionary()
        ..put(PdfName.s, mode)
        ..put(PdfName('G'), form.pdfRepresentation());
      await target.setExtGState(PdfExtGState().setSoftMask(softMask));
      return true;
    } finally {
      if (id.isNotEmpty) context.popMaskId();
    }
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = MaskSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}
