import 'css_color.dart';
import 'css_values.dart';

/// Typed parser for the portable single, solid CSS border profile.
class CraftCssBorderValue {
  final double width;
  final CraftCssColor color;
  const CraftCssBorderValue(this.width, this.color);
}

class CraftCssBorders {
  CraftCssBorders._();

  static CraftCssBorderValue? parse(Map<String, String> declarations) {
    var width = CraftCssValues.length(declarations['border-width']);
    var color = CraftCssColors.parse(declarations['border-color']);
    var solid = declarations['border-style']?.trim().toLowerCase() == 'solid';
    final shorthand = declarations['border'];
    if (shorthand != null) {
      for (final token in _tokens(shorthand)) {
        final length = CraftCssValues.length(token, fallback: -1);
        if (length >= 0) {
          width = length;
          continue;
        }
        if (token.toLowerCase() == 'solid') {
          solid = true;
          continue;
        }
        color ??= CraftCssColors.parse(token);
      }
    }
    if (!solid || width <= 0 || color == null) return null;
    return CraftCssBorderValue(width, color);
  }

  static List<String> _tokens(String source) {
    final tokens = <String>[];
    var start = -1;
    for (var index = 0; index < source.length; index++) {
      final code = source.codeUnitAt(index);
      final whitespace =
          code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;
      if (whitespace) {
        if (start >= 0) {
          tokens.add(source.substring(start, index));
          start = -1;
        }
      } else if (start < 0) {
        start = index;
      }
    }
    if (start >= 0) tokens.add(source.substring(start));
    return tokens;
  }
}
