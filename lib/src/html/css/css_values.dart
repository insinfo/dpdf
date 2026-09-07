/// Typed values used by the supported CSS layout profile.
class CssValues {
  CssValues._();

  /// Converts a non-negative CSS `pt` or `px` length into PDF points.
  static double length(String? source, {double fallback = 0}) {
    if (source == null) return fallback;
    var value = source.trim().toLowerCase();
    var factor = 1.0;
    if (value.endsWith('px')) {
      value = value.substring(0, value.length - 2).trim();
      factor = .75;
    } else if (value.endsWith('pt')) {
      value = value.substring(0, value.length - 2).trim();
    }
    final parsed = double.tryParse(value);
    return parsed == null || !parsed.isFinite || parsed < 0
        ? fallback
        : parsed * factor;
  }

  /// Parses an absolute or percentage CSS length without coupling CSS to a
  /// particular page width. Unsupported units deliberately remain [auto].
  static CssLength lengthValue(String? source) {
    if (source == null) return const CssLength.auto();
    var value = source.trim().toLowerCase();
    if (value.isEmpty || value == 'auto') return const CssLength.auto();
    if (value.endsWith('%')) {
      final fraction = double.tryParse(value.substring(0, value.length - 1));
      return fraction == null || !fraction.isFinite || fraction < 0
          ? const CssLength.auto()
          : CssLength.percent(fraction / 100);
    }
    final points = length(value, fallback: -1);
    return points < 0 ? const CssLength.auto() : CssLength.points(points);
  }

  /// Expands CSS one-to-four value shorthand in top/right/bottom/left order.
  static CssEdges edges(String? source) {
    if (source == null) return const CssEdges.zero();
    final tokens = _spaceSeparatedTokens(source);
    if (tokens.isEmpty || tokens.length > 4) return const CssEdges.zero();
    final values = tokens.map(lengthValue).toList(growable: false);
    return switch (values.length) {
      1 => CssEdges.all(values[0]),
      2 => CssEdges(values[0], values[1], values[0], values[1]),
      3 => CssEdges(values[0], values[1], values[2], values[1]),
      _ => CssEdges(values[0], values[1], values[2], values[3]),
    };
  }

  static List<String> _spaceSeparatedTokens(String source) {
    final result = <String>[];
    var start = -1;
    var depth = 0;
    for (var index = 0; index < source.length; index++) {
      final code = source.codeUnitAt(index);
      if (code == 0x28) depth++;
      if (code == 0x29 && depth > 0) depth--;
      final whitespace =
          code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;
      if (whitespace && depth == 0) {
        if (start >= 0) {
          result.add(source.substring(start, index));
          start = -1;
        }
      } else if (start < 0) {
        start = index;
      }
    }
    if (start >= 0) result.add(source.substring(start));
    return result;
  }
}

/// A CSS length which resolves only when the layout constraint is known.
class CssLength {
  final double? points;
  final double? percentage;
  const CssLength.auto()
      : points = null,
        percentage = null;
  const CssLength.points(double value)
      : points = value,
        percentage = null;
  const CssLength.percent(double value)
      : points = null,
        percentage = value;

  bool get isAuto => points == null && percentage == null;
  double resolve(double reference, {double fallback = 0}) =>
      points ?? (percentage == null ? fallback : reference * percentage!);
}

/// Typed CSS edge values in top/right/bottom/left order.
class CssEdges {
  final CssLength top;
  final CssLength right;
  final CssLength bottom;
  final CssLength left;
  const CssEdges(this.top, this.right, this.bottom, this.left);
  const CssEdges.zero()
      : top = const CssLength.points(0),
        right = const CssLength.points(0),
        bottom = const CssLength.points(0),
        left = const CssLength.points(0);
  CssEdges.all(CssLength value)
      : top = value,
        right = value,
        bottom = value,
        left = value;

  CssEdges override({
    CssLength? top,
    CssLength? right,
    CssLength? bottom,
    CssLength? left,
  }) =>
      CssEdges(top ?? this.top, right ?? this.right, bottom ?? this.bottom,
          left ?? this.left);
}
