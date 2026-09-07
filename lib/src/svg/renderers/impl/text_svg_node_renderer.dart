import 'package:dgfx/dgfx.dart';

import 'package:dpdf/src/io/font/true_type_font.dart';
import 'package:dpdf/src/kernel/font/pdf_font.dart';
import 'package:dpdf/src/kernel/font/pdf_font_factory.dart';
import 'package:dpdf/src/kernel/font/pdf_type0_font.dart';
import 'package:dpdf/src/io/font/constants/standard_fonts.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/svg/renderers/impl/abstract_svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_draw_context.dart';
import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/renderers/svg_text_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

class TextSvgNodeRenderer extends AbstractSvgNodeRenderer
    implements SvgTextNodeRenderer {
  @override
  Future<void> doDraw(SvgDrawContext context) async {
    final text = getAttribute('_text') ?? '';
    if (text.isEmpty) return;
    final canvas = context.getCurrentCanvas();
    if (canvas.resources == null || canvas.getDocument() == null) return;

    final size = getCurrentFontSize(context);
    final x = parseHorizontalLength(
        getAttributeOrDefault(SvgAttributes.X, '0'), context);
    final y = parseVerticalLength(
        getAttributeOrDefault(SvgAttributes.Y, '0'), context);
    final font = await _resolveFont(context);
    canvas.beginText();
    await canvas.setFontAndSize(font, size);
    canvas.moveText(x, y);
    canvas.showText(text);
    canvas.endText();
  }

  Future<PdfFont> _resolveFont(SvgDrawContext context) async {
    final collection = context.fontCollection;
    if (collection != null) {
      final families = (getAttribute(SvgAttributes.FONT_FAMILY) ?? '')
          .split(',')
          .map((value) =>
              value.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), ''))
          .where((value) => value.isNotEmpty)
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
          // Uma face que o dgfx entende ainda pode usar tabelas que o escritor
          // PDF não incorpora; nesse caso a fonte padrão mantém o texto.
        }
      }
    }
    return PdfFontFactory.createFont(StandardFonts.HELVETICA);
  }

  @override
  Rectangle? getObjectBoundingBox(SvgDrawContext context) => null;

  @override
  SvgNodeRenderer createDeepCopy() {
    final copy = TextSvgNodeRenderer();
    deepCopyAttributesAndStyles(copy);
    return copy;
  }
}
