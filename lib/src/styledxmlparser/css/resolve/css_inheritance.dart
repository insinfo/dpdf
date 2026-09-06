import 'package:pdfcraft/src/styledxmlparser/css/common_css_constants.dart';
import 'package:pdfcraft/src/styledxmlparser/css/resolve/style_inheritance.dart';
import 'package:pdfcraft/src/styledxmlparser/css/util/css_variable_util.dart';

class CraftCssInheritance implements CraftStyleInheritance {
  static const Set<String> _INHERITABLE_PROPERTIES = {
    CraftCommonCssConstants.COLOR,
    CraftCommonCssConstants.VISIBILITY,
    CraftCommonCssConstants.HANGING_PUNCTUATION,
    CraftCommonCssConstants.HYPHENS,
    CraftCommonCssConstants.LETTER_SPACING,
    CraftCommonCssConstants.LINE_HEIGHT,
    CraftCommonCssConstants.OVERFLOW_WRAP,
    CraftCommonCssConstants.TAB_SIZE,
    CraftCommonCssConstants.TEXT_ALIGN,
    CraftCommonCssConstants.TEXT_ALIGN_LAST,
    CraftCommonCssConstants.TEXT_INDENT,
    CraftCommonCssConstants.TEXT_JUSTIFY,
    CraftCommonCssConstants.TEXT_TRANSFORM,
    CraftCommonCssConstants.WHITE_SPACE,
    CraftCommonCssConstants.WORD_BREAK,
    CraftCommonCssConstants.WORD_SPACING,
    CraftCommonCssConstants.WORDWRAP,
    CraftCommonCssConstants.TEXT_SHADOW,
    CraftCommonCssConstants.TEXT_UNDERLINE_POSITION,
    CraftCommonCssConstants.FONT,
    CraftCommonCssConstants.FONT_FAMILY,
    CraftCommonCssConstants.FONT_FEATURE_SETTINGS,
    CraftCommonCssConstants.FONT_KERNING,
    CraftCommonCssConstants.FONT_LANGUAGE_OVERRIDE,
    CraftCommonCssConstants.FONT_SIZE,
    CraftCommonCssConstants.FONT_SIZE_ADJUST,
    CraftCommonCssConstants.FONT_STRETCH,
    CraftCommonCssConstants.FONT_STYLE,
    CraftCommonCssConstants.FONT_SYNTHESIS,
    CraftCommonCssConstants.FONT_VARIANT,
    CraftCommonCssConstants.FONT_VARIANT_ALTERNATES,
    CraftCommonCssConstants.FONT_VARIANT_CAPS,
    CraftCommonCssConstants.FONT_VARIANT_EAST_ASIAN,
    CraftCommonCssConstants.FONT_VARIANT_LIGATURES,
    CraftCommonCssConstants.FONT_VARIANT_NUMERIC,
    CraftCommonCssConstants.FONT_VARIANT_POSITION,
    CraftCommonCssConstants.FONT_WEIGHT,
    CraftCommonCssConstants.DIRECTION,
    CraftCommonCssConstants.TEXT_ORIENTATION,
    CraftCommonCssConstants.TEXT_COMBINE_UPRIGHT,
    CraftCommonCssConstants.UNICODE_BIDI,
    CraftCommonCssConstants.WRITING_MODE,
    CraftCommonCssConstants.BORDER_COLLAPSE,
    CraftCommonCssConstants.BORDER_SPACING,
    CraftCommonCssConstants.CAPTION_SIDE,
    CraftCommonCssConstants.EMPTY_CELLS,
    CraftCommonCssConstants.LIST_STYLE,
    CraftCommonCssConstants.LIST_STYLE_IMAGE,
    CraftCommonCssConstants.LIST_STYLE_POSITION,
    CraftCommonCssConstants.LIST_STYLE_TYPE,
    CraftCommonCssConstants.QUOTES,
    CraftCommonCssConstants.ORPHANS,
    CraftCommonCssConstants.WIDOWS,
  };

  @override
  bool isInheritable(String propertyIdentifier) {
    return _INHERITABLE_PROPERTIES.contains(propertyIdentifier) ||
        CssVariableUtil.isCssVariable(propertyIdentifier);
  }
}
