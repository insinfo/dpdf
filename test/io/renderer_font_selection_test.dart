import 'package:pdfcraft/src/kernel/geom/affine_transform.dart';
import 'package:pdfcraft/src/kernel/font/pdf_type1_font.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_dictionary.dart';
import 'package:pdfcraft/src/io/font/type1_font.dart';
import 'package:pdfcraft/src/io/font/font_encoding.dart';
import 'package:pdfcraft/src/io/font/otf/glyph.dart';
import 'package:pdfcraft/src/layout/element/list.dart';
import 'package:pdfcraft/src/layout/element/list_item.dart';
import 'package:pdfcraft/src/layout/properties/list_numbering_type.dart';
import 'package:pdfcraft/src/layout/renderer/list_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/list_item_renderer.dart';
import 'package:pdfcraft/src/layout/renderer/text_renderer.dart';
import 'package:test/test.dart';

class GlyphFixture extends CraftPdfType1Font {
  final available = {
    65: CraftGlyph(1, 600, 65),
    0x1f600: CraftGlyph(2, 700, 0x1f600)
  };
  GlyphFixture() : super.fromDictionary(CraftPdfDictionary());
  @override
  CraftGlyph? getGlyph(int unicode) => available[unicode];
  @override
  bool containsGlyph(int unicode) => available.containsKey(unicode);
}

void main() {
  test('Affine classification notices direct coefficient changes', () {
    final value = CraftAffineTransform();
    expect(value.getTransformType(), CraftAffineTransform.typeIdentity);
    value.m02 = 10;
    expect(value.getTransformType(), CraftAffineTransform.typeTranslation);
    value.m00 = 2;
    expect(
        value.getTransformType(),
        CraftAffineTransform.typeTranslation |
            CraftAffineTransform.typeGeneralScale);
    value.m01 = 1;
    expect(value.getTransformType(), CraftAffineTransform.typeGeneralTransform);
  });
  test(
      'Affine classification preserves rotation, uniform scale and reflection flags',
      () {
    expect(
        CraftAffineTransform.fromValues(0, 2, -2, 0, 0, 0).getTransformType(),
        CraftAffineTransform.typeQuadrantRotation |
            CraftAffineTransform.typeUniformScale);
    expect(
        CraftAffineTransform.fromValues(-1, 0, 0, 1, 0, 0).getTransformType(),
        CraftAffineTransform.typeQuadrantRotation |
            CraftAffineTransform.typeFlip);
  });
  test(
      'Glyph appending counts UTF16 units while producing supplementary glyphs',
      () {
    final font = GlyphFixture();
    final glyphs = <CraftGlyph>[];
    expect(font.appendGlyphs('A😀?A', 0, 4, glyphs), 3);
    expect(glyphs.map((glyph) => glyph.getUnicode()), [65, 0x1f600]);
    glyphs.clear();
    expect(font.appendGlyphs('A😀A', 1, 2, glyphs), 2);
    expect(glyphs.single.getUnicode(), 0x1f600);
  });
  test(
      'Glyph appending skips unmapped whitespace and preserves byte-specific semantics',
      () {
    final glyphs = <CraftGlyph>[];
    expect(GlyphFixture().appendGlyphs('A\nA', 0, 2, glyphs), 3);
    expect(glyphs.length, 2);
    final font = CraftPdfType1Font(
        CraftType1Font.createBuiltInFont('Helvetica'),
        CraftFontEncoding.FONT_SPECIFIC);
    glyphs.clear();
    expect(font.appendGlyphs(String.fromCharCode(0x141), 0, 0, glyphs), 1);
    expect(glyphs.single.getCode(), 65);
  });
  test('List numbering selects symbol families and keeps decimal text renderer',
      () {
    final choices = {
      CraftListNumberingType.GREEK_LOWER: 'Symbol',
      CraftListNumberingType.GREEK_UPPER: 'Symbol',
      CraftListNumberingType.ZAPF_DINGBATS_1: 'ZapfDingbats',
      CraftListNumberingType.ZAPF_DINGBATS_2: 'ZapfDingbats',
      CraftListNumberingType.ZAPF_DINGBATS_3: 'ZapfDingbats',
      CraftListNumberingType.ZAPF_DINGBATS_4: 'ZapfDingbats',
    };
    for (final entry in choices.entries) {
      final list = CraftListRenderer(CraftList(entry.key));
      final symbol = list.makeListSymbolRenderer(
          1, CraftListItemRenderer(CraftListItem('item')))!;
      final dynamic renderer = symbol.getChildRenderers()[1];
      expect(renderer.constantFontName, entry.value);
    }
    final list = CraftListRenderer(CraftList(CraftListNumberingType.DECIMAL));
    final symbol = list.makeListSymbolRenderer(
        1, CraftListItemRenderer(CraftListItem('item')))!;
    expect(symbol.getChildRenderers()[1].runtimeType, CraftTextRenderer);
  });
}
