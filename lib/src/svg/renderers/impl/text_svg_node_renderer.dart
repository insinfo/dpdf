import 'package:dgfx/dgfx.dart';
import 'package:dpdf/src/io/font/constants/standard_fonts.dart';
import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/kernel/font/pdf_font.dart';
import 'package:dpdf/src/kernel/font/pdf_font_factory.dart';
import 'package:dpdf/src/kernel/font/pdf_type0_font.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_branch_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_text_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Contêiner de `<text>` ou `<tspan>`. Nós textuais separados preservam a
/// ordem do DOM quando texto direto e tspans aparecem intercalados.
class TextSvgNodeRenderer extends AbstractBranchSvgNodeRenderer
    implements SvgTextNodeRenderer {
  final bool root;
  TextSvgNodeRenderer({this.root = false});

  @override
  Future<void> doDraw(SvgDrawContext context) async {
    if (root) context.resetTextMove();
    final cursor = context.getTextMove();
    var x = cursor[0];
    var y = cursor[1];
    final xRaw = getAttribute(SvgAttributes.X);
    final yRaw = getAttribute(SvgAttributes.Y);
    if (xRaw != null) x = parseHorizontalLength(xRaw, context);
    if (yRaw != null) y = parseVerticalLength(yRaw, context);
    x += parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.DX, '0'), context);
    y += parseVerticalLength(
        getAttributeOrDefault(SvgAttributes.DY, '0'), context);
    context.resetTextMove();
    context.addTextMove(x, y);
    await super.doDraw(context);
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = TextSvgNodeRenderer(root: root);
    deepCopyAttributesAndStyles(copy);
    deepCopyChildren(copy);
    return copy;
  }
}

class TextLeafSvgNodeRenderer extends AbstractSvgNodeRenderer
    implements SvgTextNodeRenderer {
  @override
  Future<void> doDraw(SvgDrawContext context) async {
    final text = getAttribute('_text') ?? '';
    if (text.isEmpty) return;
    final canvas = context.getCurrentCanvas();
    if (canvas.resources == null || canvas.getDocument() == null) return;

    final cursor = context.getTextMove();
    final x = cursor[0];
    final y = cursor[1];

    final size = getCurrentFontSize(context);
    final font = await _resolveFont(context);
    canvas.beginText();
    await canvas.setFontAndSize(font, size);
    // The SVG root flips the canvas Y axis so geometric coordinates grow
    // downward. Counter-flip glyph space around the requested baseline;
    // otherwise PDF viewers draw every SVG label upside down.
    canvas.setTextMatrix(1, 0, 0, -1, x, y);
    canvas.showText(text);
    canvas.endText();
    context.resetTextMove();
    context.addTextMove(x + font.getWidthPoint(text, size), y);
  }

  Future<PdfFont> _resolveFont(SvgDrawContext context) async {
    final collection = context.fontCollection;
    if (collection != null) {
      final families = (getAttribute(SvgAttributes.FONT_FAMILY) ?? '')
          .split(',')
          .map((v) => v.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), ''))
          .where((v) => v.isNotEmpty)
          .toList();
      final weightRaw = getAttribute(SvgAttributes.FONT_WEIGHT) ?? '400';
      final weight = int.tryParse(weightRaw) ??
          (weightRaw.toLowerCase() == 'bold' ? 700 : 400);
      final style =
          (getAttribute(SvgAttributes.FONT_STYLE) ?? '').toLowerCase();
      final slant = style == 'italic'
          ? BLFontSlant.italic
          : style == 'oblique'
              ? BLFontSlant.oblique
              : BLFontSlant.normal;
      final face = await collection.resolve(BLFontQuery(
          families.isEmpty ? const ['sans-serif'] : families,
          weight: weight,
          slant: slant));
      if (face != null && face.hasTrueTypeOutlines) {
        try {
          return PdfType0Font(TrueTypeFont.fromBytes(face.data), 'Identity-H');
        } on Object {
          // O incorporador PDF pode aceitar menos formatos que o dgfx.
        }
      }
    }
    return PdfFontFactory.createFont(StandardFonts.HELVETICA);
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = TextLeafSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
