/// Typed values used by the supported CSS layout profile.
class CraftCssValues {
  CraftCssValues._();

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
  static CraftCssLength lengthValue(String? source) {
    if (source == null) return const CraftCssLength.auto();
    var value = source.trim().toLowerCase();
    if (value.isEmpty || value == 'auto') return const CraftCssLength.auto();
    if (value.endsWith('%')) {
      final fraction = double.tryParse(value.substring(0, value.length - 1));
      return fraction == null || !fraction.isFinite || fraction < 0
          ? const CraftCssLength.auto()
          : CraftCssLength.percent(fraction / 100);
    }
    final points = length(value, fallback: -1);
    return points < 0
        ? const CraftCssLength.auto()
        : CraftCssLength.points(points);
  }

  /// Expands CSS one-to-four value shorthand in top/right/bottom/left order.
  static CraftCssEdges edges(String? source) {
    if (source == null) return const CraftCssEdges.zero();
    final tokens = _spaceSeparatedTokens(source);
    if (tokens.isEmpty || tokens.length > 4) return const CraftCssEdges.zero();
    final values = tokens.map(lengthValue).toList(growable: false);
    return switch (values.length) {
      1 => CraftCssEdges.all(values[0]),
      2 => CraftCssEdges(values[0], values[1], values[0], values[1]),
      3 => CraftCssEdges(values[0], values[1], values[2], values[1]),
      _ => CraftCssEdges(values[0], values[1], values[2], values[3]),
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
class CraftCssLength {
  final double? points;
  final double? percentage;
  const CraftCssLength.auto()
      : points = null,
        percentage = null;
  const CraftCssLength.points(double value)
      : points = value,
        percentage = null;
  const CraftCssLength.percent(double value)
      : points = null,
        percentage = value;

  bool get isAuto => points == null && percentage == null;
  double resolve(double reference, {double fallback = 0}) =>
      points ?? (percentage == null ? fallback : reference * percentage!);
}

/// Typed CSS edge values in top/right/bottom/left order.
class CraftCssEdges {
  final CraftCssLength top;
  final CraftCssLength right;
  final CraftCssLength bottom;
  final CraftCssLength left;
  const CraftCssEdges(this.top, this.right, this.bottom, this.left);
  const CraftCssEdges.zero()
      : top = const CraftCssLength.points(0),
        right = const CraftCssLength.points(0),
        bottom = const CraftCssLength.points(0),
        left = const CraftCssLength.points(0);
  CraftCssEdges.all(CraftCssLength value)
      : top = value,
        right = value,
        bottom = value,
        left = value;

  CraftCssEdges override({
    CraftCssLength? top,
    CraftCssLength? right,
    CraftCssLength? bottom,
    CraftCssLength? left,
  }) =>
      CraftCssEdges(top ?? this.top, right ?? this.right, bottom ?? this.bottom,
          left ?? this.left);
}
