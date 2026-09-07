/// Device-RGB color used by the portable HTML/CSS profile.
class CraftCssColor {
  final double red;
  final double green;
  final double blue;
  const CraftCssColor(this.red, this.green, this.blue);

  static const black = CraftCssColor(0, 0, 0);
  static const white = CraftCssColor(1, 1, 1);
}

/// Parses the deliberately small, deterministic color grammar supported by
/// HTML-to-PDF: named colors, #rgb, #rrggbb and rgb(r,g,b).
class CraftCssColors {
  CraftCssColors._();

  static CraftCssColor? parse(String? source) {
    if (source == null) return null;
    final value = source.trim().toLowerCase();
    if (value == 'transparent') return null;
    final named = _named[value];
    if (named != null) return named;
    if (value.startsWith('#')) return _hex(value);
    if (value.startsWith('rgb(') && value.endsWith(')')) {
      return _rgb(value.substring(4, value.length - 1));
    }
    return null;
  }

  static CraftCssColor? _hex(String value) {
    final source = value.substring(1);
    if (source.length == 3) {
      final r = _hexDigit(source.codeUnitAt(0));
      final g = _hexDigit(source.codeUnitAt(1));
      final b = _hexDigit(source.codeUnitAt(2));
      return r == null || g == null || b == null
          ? null
          : CraftCssColor(r / 15, g / 15, b / 15);
    }
    if (source.length != 6) return null;
    final channels = <int>[];
    for (var index = 0; index < 6; index += 2) {
      final high = _hexDigit(source.codeUnitAt(index));
      final low = _hexDigit(source.codeUnitAt(index + 1));
      if (high == null || low == null) return null;
      channels.add(high * 16 + low);
    }
    return CraftCssColor(
        channels[0] / 255, channels[1] / 255, channels[2] / 255);
  }

  static int? _hexDigit(int value) {
    if (value >= 0x30 && value <= 0x39) return value - 0x30;
    if (value >= 0x61 && value <= 0x66) return value - 0x61 + 10;
    return null;
  }

  static CraftCssColor? _rgb(String source) {
    final parts = source.split(',');
    if (parts.length != 3) return null;
    final channels = <double>[];
    for (final part in parts) {
      final value = double.tryParse(part.trim());
      if (value == null || !value.isFinite || value < 0 || value > 255) {
        return null;
      }
      channels.add(value / 255);
    }
    return CraftCssColor(channels[0], channels[1], channels[2]);
  }

  static const _named = <String, CraftCssColor>{
    'black': CraftCssColor.black,
    'white': CraftCssColor.white,
    'red': CraftCssColor(1, 0, 0),
    'green': CraftCssColor(0, .5, 0),
    'blue': CraftCssColor(0, 0, 1),
    'yellow': CraftCssColor(1, 1, 0),
    'gray': CraftCssColor(.5, .5, .5),
    'grey': CraftCssColor(.5, .5, .5),
  };
}
