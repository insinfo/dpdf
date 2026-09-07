/// Immutable layout plan produced before PDF painting.
class HtmlLayoutRow<T> {
  final List<T> items;
  const HtmlLayoutRow(this.items);
}

/// Stateless algorithms for the supported CSS flex and grid profiles.
///
/// The DOM/CSS layer selects the algorithm and PDF painting consumes the rows;
/// neither layer needs to know the other's representation.
class HtmlLayoutPlan {
  HtmlLayoutPlan._();

  static List<HtmlLayoutRow<T>> flex<T>(List<T> items,
      {String direction = 'row'}) {
    if (direction.toLowerCase().startsWith('column')) {
      return [
        for (final item in items) HtmlLayoutRow([item])
      ];
    }
    return items.isEmpty ? const [] : [HtmlLayoutRow(items)];
  }

  /// Groups row-direction flex items without inspecting DOM or CSS objects.
  static List<HtmlLayoutRow<T>> flexRows<T>(List<T> items,
      {required double availableWidth,
      required double Function(T item) widthOf,
      required double gap,
      required bool wrap}) {
    if (items.isEmpty) return const [];
    if (!wrap) return [HtmlLayoutRow(items)];
    final rows = <HtmlLayoutRow<T>>[];
    var row = <T>[];
    var used = 0.0;
    for (final item in items) {
      final itemWidth = widthOf(item).clamp(0.0, availableWidth).toDouble();
      final required = row.isEmpty ? itemWidth : gap + itemWidth;
      if (row.isNotEmpty && used + required > availableWidth) {
        rows.add(HtmlLayoutRow(List.unmodifiable(row)));
        row = <T>[];
        used = 0;
      }
      used += row.isEmpty ? itemWidth : gap + itemWidth;
      row.add(item);
    }
    if (row.isNotEmpty) rows.add(HtmlLayoutRow(List.unmodifiable(row)));
    return rows;
  }

  static List<HtmlLayoutRow<T>> grid<T>(List<T> items, int columns) {
    if (columns < 1) throw ArgumentError.value(columns, 'columns');
    return [
      for (var index = 0; index < items.length; index += columns)
        HtmlLayoutRow(
            items.sublist(index, (index + columns).clamp(0, items.length)))
    ];
  }

  static int gridColumns(String? template) {
    return _tracks(template).length;
  }

  /// Resolves the supported `grid-template-columns` profile into PDF points.
  ///
  /// The parser deliberately walks CSS characters instead of splitting with a
  /// regular expression: whitespace inside `repeat(...)` is part of its track
  /// list. It accepts `repeat(n, track-list)`, fractional `fr` tracks and
  /// fixed `pt`/`px` tracks. Unsupported or empty input has one `1fr` track.
  static List<double> gridTrackWidths(String? template, double width,
      {double gap = 0}) {
    if (!width.isFinite || width < 0) {
      throw ArgumentError.value(
          width, 'width', 'must be finite and nonnegative');
    }
    if (!gap.isFinite || gap < 0) {
      throw ArgumentError.value(gap, 'gap', 'must be finite and nonnegative');
    }
    final tracks = _tracks(template);
    final gaps = gap * (tracks.length - 1);
    final available = width > gaps ? width - gaps : 0.0;
    final fixed = tracks.fold<double>(0, (sum, track) => sum + track.points);
    final fractions = tracks.fold<double>(0, (sum, track) => sum + track.fr);
    final unit = fractions == 0 || available <= fixed
        ? 0.0
        : (available - fixed) / fractions;
    return List.unmodifiable([
      for (final track in tracks) track.points + track.fr * unit,
    ]);
  }

  static List<_GridTrack> _tracks(String? template) {
    final source = template?.trim() ?? '';
    if (source.isEmpty) return const [_GridTrack.fraction(1)];
    final tracks = _GridTrackParser(source).parse();
    return tracks.isEmpty ? const [_GridTrack.fraction(1)] : tracks;
  }
}

class _GridTrack {
  final double points;
  final double fr;
  const _GridTrack(this.points, this.fr);
  const _GridTrack.fraction(double fr) : this(0, fr);
}

class _GridTrackParser {
  final String source;
  int _position = 0;
  _GridTrackParser(this.source);

  List<_GridTrack> parse() {
    final tracks = _list(stopAtClosingParen: false);
    _skipWhitespace();
    return _position == source.length ? tracks : const [];
  }

  List<_GridTrack> _list({required bool stopAtClosingParen}) {
    final result = <_GridTrack>[];
    while (true) {
      _skipWhitespace();
      if (_position == source.length ||
          (stopAtClosingParen && source.codeUnitAt(_position) == 41)) {
        return result;
      }
      final repeated = _repeat();
      if (repeated != null) {
        result.addAll(repeated);
        continue;
      }
      final token = _token();
      final track = _track(token);
      if (track == null) return const [];
      result.add(track);
    }
  }

  List<_GridTrack>? _repeat() {
    const word = 'repeat(';
    if (_position + word.length > source.length ||
        source.substring(_position, _position + word.length).toLowerCase() !=
            word) {
      return null;
    }
    _position += word.length;
    _skipWhitespace();
    final countStart = _position;
    while (_position < source.length) {
      final code = source.codeUnitAt(_position);
      if (code < 48 || code > 57) break;
      _position++;
    }
    final count = int.tryParse(source.substring(countStart, _position));
    _skipWhitespace();
    if (count == null ||
        count < 1 ||
        count > 4096 ||
        _position == source.length ||
        source.codeUnitAt(_position++) != 44) {
      return const [];
    }
    final repeated = _list(stopAtClosingParen: true);
    if (_position == source.length ||
        source.codeUnitAt(_position++) != 41 ||
        repeated.isEmpty ||
        repeated.length * count > 4096) {
      return const [];
    }
    return [for (var index = 0; index < count; index++) ...repeated];
  }

  String _token() {
    final start = _position;
    while (_position < source.length) {
      final code = source.codeUnitAt(_position);
      if (_whitespace(code) || code == 41 || code == 44) break;
      _position++;
    }
    return source.substring(start, _position).toLowerCase();
  }

  _GridTrack? _track(String token) {
    if (token.isEmpty) return null;
    String unit = '';
    if (token.endsWith('fr')) {
      unit = 'fr';
    } else if (token.endsWith('px') || token.endsWith('pt')) {
      unit = token.substring(token.length - 2);
    } else if (token == '0') {
      return const _GridTrack(0, 0);
    } else {
      return null;
    }
    final valueText = token.substring(0, token.length - unit.length);
    final value = double.tryParse(valueText);
    if (value == null || !value.isFinite || value < 0) return null;
    if (unit == 'fr') return _GridTrack.fraction(value);
    return _GridTrack(unit == 'px' ? value * .75 : value, 0);
  }

  void _skipWhitespace() {
    while (_position < source.length &&
        _whitespace(source.codeUnitAt(_position))) {
      _position++;
    }
  }

  bool _whitespace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;
}
