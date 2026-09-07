/// Device-RGB color used by the portable HTML/CSS profile.
class CssColor {
  final double red;
  final double green;
  final double blue;
  const CssColor(this.red, this.green, this.blue);

  static const black = CssColor(0, 0, 0);
  static const white = CssColor(1, 1, 1);
}

/// Parses the deliberately small, deterministic color grammar supported by
/// HTML-to-PDF: named colors, #rgb, #rrggbb and rgb(r,g,b).
class CssColors {
  CssColors._();

  static CssColor? parse(String? source) {
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

  static CssColor? _hex(String value) {
    final source = value.substring(1);
    if (source.length == 3) {
      final r = _hexDigit(source.codeUnitAt(0));
      final g = _hexDigit(source.codeUnitAt(1));
      final b = _hexDigit(source.codeUnitAt(2));
      return r == null || g == null || b == null
          ? null
          : CssColor(r / 15, g / 15, b / 15);
    }
    if (source.length != 6) return null;
    final channels = <int>[];
    for (var index = 0; index < 6; index += 2) {
      final high = _hexDigit(source.codeUnitAt(index));
      final low = _hexDigit(source.codeUnitAt(index + 1));
      if (high == null || low == null) return null;
      channels.add(high * 16 + low);
    }
    return CssColor(channels[0] / 255, channels[1] / 255, channels[2] / 255);
  }

  static int? _hexDigit(int value) {
    if (value >= 0x30 && value <= 0x39) return value - 0x30;
    if (value >= 0x61 && value <= 0x66) return value - 0x61 + 10;
    return null;
  }

  static CssColor? _rgb(String source) {
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
    return CssColor(channels[0], channels[1], channels[2]);
  }

  static const _named = <String, CssColor>{
    'black': CssColor.black,
    'white': CssColor.white,
    'red': CssColor(1, 0, 0),
    'green': CssColor(0, .5, 0),
    'blue': CssColor(0, 0, 1),
    'yellow': CssColor(1, 1, 0),
    'gray': CssColor(.5, .5, .5),
    'grey': CssColor(.5, .5, .5),
  };
}
