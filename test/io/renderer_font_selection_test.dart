import 'package:dpdf/src/kernel/geom/affine_transform.dart';
import 'package:dpdf/src/kernel/font/pdf_type1_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/io/font/type1_font.dart';
import 'package:dpdf/src/io/font/font_encoding.dart';
import 'package:dpdf/src/io/font/otf/glyph.dart';
import 'package:dpdf/src/layout/element/list.dart';
import 'package:dpdf/src/layout/element/list_item.dart';
import 'package:dpdf/src/layout/properties/list_numbering_type.dart';
import 'package:dpdf/src/layout/renderer/list_renderer.dart';
import 'package:dpdf/src/layout/renderer/list_item_renderer.dart';
import 'package:dpdf/src/layout/renderer/text_renderer.dart';
import 'package:test/test.dart';

class GlyphFixture extends PdfType1Font {
  final available = {65: Glyph(1, 600, 65), 0x1f600: Glyph(2, 700, 0x1f600)};
  GlyphFixture() : super.fromDictionary(PdfDictionary());
  @override
  Glyph? getGlyph(int unicode) => available[unicode];
  @override
  bool containsGlyph(int unicode) => available.containsKey(unicode);
}

void main() {
  test('Affine classification notices direct coefficient changes', () {
    final value = AffineTransform();
    expect(value.getTransformType(), AffineTransform.typeIdentity);
    value.m02 = 10;
    expect(value.getTransformType(), AffineTransform.typeTranslation);
    value.m00 = 2;
    expect(value.getTransformType(),
        AffineTransform.typeTranslation | AffineTransform.typeGeneralScale);
    value.m01 = 1;
    expect(value.getTransformType(), AffineTransform.typeGeneralTransform);
  });
  test(
      'Affine classification preserves rotation, uniform scale and reflection flags',
      () {
    expect(
        AffineTransform.fromValues(0, 2, -2, 0, 0, 0).getTransformType(),
        AffineTransform.typeQuadrantRotation |
            AffineTransform.typeUniformScale);
    expect(AffineTransform.fromValues(-1, 0, 0, 1, 0, 0).getTransformType(),
        AffineTransform.typeQuadrantRotation | AffineTransform.typeFlip);
  });
  test(
      'Glyph appending counts UTF16 units while producing supplementary glyphs',
      () {
    final font = GlyphFixture();
    final glyphs = <Glyph>[];
    expect(font.appendGlyphs('A😀?A', 0, 4, glyphs), 3);
    expect(glyphs.map((glyph) => glyph.getUnicode()), [65, 0x1f600]);
    glyphs.clear();
    expect(font.appendGlyphs('A😀A', 1, 2, glyphs), 2);
    expect(glyphs.single.getUnicode(), 0x1f600);
  });
  test(
      'Glyph appending skips unmapped whitespace and preserves byte-specific semantics',
      () {
    final glyphs = <Glyph>[];
    expect(GlyphFixture().appendGlyphs('A\nA', 0, 2, glyphs), 3);
    expect(glyphs.length, 2);
    final font = PdfType1Font(
        Type1Font.createBuiltInFont('Helvetica'), FontEncoding.FONT_SPECIFIC);
    glyphs.clear();
    expect(font.appendGlyphs(String.fromCharCode(0x141), 0, 0, glyphs), 1);
    expect(glyphs.single.getCode(), 65);
  });
  test('List numbering selects symbol families and keeps decimal text renderer',
      () {
    final choices = {
      ListNumberingType.GREEK_LOWER: 'Symbol',
      ListNumberingType.GREEK_UPPER: 'Symbol',
      ListNumberingType.ZAPF_DINGBATS_1: 'ZapfDingbats',
      ListNumberingType.ZAPF_DINGBATS_2: 'ZapfDingbats',
      ListNumberingType.ZAPF_DINGBATS_3: 'ZapfDingbats',
      ListNumberingType.ZAPF_DINGBATS_4: 'ZapfDingbats',
    };
    for (final entry in choices.entries) {
      final list = ListRenderer(PdfList(entry.key));
      final symbol =
          list.makeListSymbolRenderer(1, ListItemRenderer(ListItem('item')))!;
      final dynamic renderer = symbol.getChildRenderers()[1];
      expect(renderer.constantFontName, entry.value);
    }
    final list = ListRenderer(PdfList(ListNumberingType.DECIMAL));
    final symbol =
        list.makeListSymbolRenderer(1, ListItemRenderer(ListItem('item')))!;
    expect(symbol.getChildRenderers()[1].runtimeType, TextRenderer);
  });
}
