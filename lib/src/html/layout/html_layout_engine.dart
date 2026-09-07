import '../model/html_box.dart';
import '../model/html_text.dart';
import 'html_box_geometry.dart';
import 'html_display_list.dart';
import 'html_layout_plan.dart';

/// CSS box layout profile for text, block flow, flex rows/columns and grids.
///
/// The engine returns a display list rather than writing PDF operators, which
/// keeps pagination and painting independent from layout decisions.
class CraftHtmlLayoutEngine {
  final double availableWidth;
  final List<CraftHtmlTextFragment> _fragments = [];
  final List<CraftHtmlBoxDecoration> _decorations = [];
  final List<CraftHtmlImageFragment> _images = [];
  double _cursor = 0;

  CraftHtmlLayoutEngine(this.availableWidth) : assert(availableWidth > 0);

  List<CraftHtmlTextFragment> layout(List<CraftHtmlBox> boxes) {
    return layoutDisplayList(boxes).textFragments;
  }

  CraftHtmlDisplayList layoutDisplayList(List<CraftHtmlBox> boxes) {
    for (final box in boxes) {
      _layout(box, 0, availableWidth);
    }
    return CraftHtmlDisplayList(List.unmodifiable(_fragments),
        List.unmodifiable(_decorations), List.unmodifiable(_images));
  }

  double _layout(CraftHtmlBox box, double x, double width) {
    if (box.role == CraftHtmlBoxRole.table) return _table(box, x, width);
    if (box.isImage) return _image(box, x, width);
    if (box.isText) {
      return _paragraph(box.text!, box.style.text, x, width,
          linkTarget: box.linkTarget);
    }
    switch (box.style.display) {
      case CraftHtmlDisplay.none:
        return 0;
      case CraftHtmlDisplay.flex:
        return _flex(box, x, width);
      case CraftHtmlDisplay.grid:
        return _grid(box, x, width);
      case CraftHtmlDisplay.inline:
      case CraftHtmlDisplay.block:
        return _flow(box, x, width);
    }
  }

  double _image(CraftHtmlBox box, double x, double width) {
    final source = box.image!;
    final resolvedWidth = source.width.clamp(1.0, width).toDouble();
    final resolvedHeight = source.height * resolvedWidth / source.width;
    final top = _cursor;
    _images.add(
        CraftHtmlImageFragment(source, x, top, resolvedWidth, resolvedHeight));
    _cursor += resolvedHeight;
    return resolvedHeight;
  }

  double _flow(CraftHtmlBox box, double x, double width) {
    final geometry = CraftHtmlBoxGeometry.resolve(box.style, x, width);
    final start = _cursor;
    _cursor += geometry.marginTop + geometry.paddingTop;
    final inline = <CraftHtmlBox>[];
    void flushInline() {
      if (inline.isEmpty) return;
      _inlineFlow(
          inline, geometry.x, geometry.contentWidth, box.style.textAlign);
      inline.clear();
    }

    // Preserve the DOM sequence and the typography of nested inline tags.
    // Flattening direct text at the container style loses <strong>, <em> and
    // nested span styles, including when the container is a flex/grid item.
    for (final child in box.children) {
      final leaves = _inlineLeaves(child);
      if (leaves != null) {
        inline.addAll(leaves);
      } else {
        flushInline();
        _layout(child, geometry.x, geometry.contentWidth);
      }
    }
    flushInline();
    if (box.style.display == CraftHtmlDisplay.block && _cursor > start) {
      _cursor += box.style.text.fontSize * .35;
    }
    _cursor += geometry.paddingBottom;
    _addDecoration(box, geometry, start + geometry.marginTop, _cursor);
    _cursor += geometry.marginBottom;
    return _cursor - start;
  }

  List<CraftHtmlBox>? _inlineLeaves(CraftHtmlBox box) {
    if (box.isText) return [box];
    if (box.isImage) return null;
    if (box.style.display != CraftHtmlDisplay.inline) return null;
    final result = <CraftHtmlBox>[];
    for (final child in box.children) {
      final leaves = _inlineLeaves(child);
      if (leaves == null) return null;
      result.addAll(leaves);
    }
    return result;
  }

  void _inlineFlow(List<CraftHtmlBox> leaves, double x, double width,
      CraftHtmlTextAlign textAlign) {
    final line = <_InlineWord>[];
    var used = 0.0;
    var lineHeight = 0.0;

    void flush() {
      if (line.isEmpty) return;
      _cursor += lineHeight;
      final alignmentOffset = switch (textAlign) {
        CraftHtmlTextAlign.center => (width - used) / 2,
        CraftHtmlTextAlign.end => width - used,
        _ => 0.0,
      };
      for (final word in line) {
        _fragments.add(CraftHtmlTextFragment(
            word.text, word.style, x + alignmentOffset + word.offset, _cursor,
            linkTarget: word.linkTarget));
      }
      line.clear();
      used = 0;
      lineHeight = 0;
    }

    for (final leaf in leaves) {
      final style = leaf.style.text;
      final forcedLines = leaf.text!.split('\n');
      for (var index = 0; index < forcedLines.length; index++) {
        for (final word in CraftHtmlText.words(forcedLines[index])) {
          if (word.isEmpty) continue;
          final glyphWidth = word.length * style.fontSize * .52;
          final space = line.isEmpty ? 0.0 : style.fontSize * .52;
          if (line.isNotEmpty && used + space + glyphWidth > width) flush();
          final offset = used + (line.isEmpty ? 0 : style.fontSize * .52);
          line.add(_InlineWord(word, style, offset, leaf.linkTarget));
          used = offset + glyphWidth;
          final height = style.fontSize * 1.35;
          if (height > lineHeight) lineHeight = height;
        }
        if (index + 1 < forcedLines.length) flush();
      }
    }
    flush();
  }

  double _flex(CraftHtmlBox box, double x, double width) {
    if (box.children.isEmpty) return 0;
    if (box.style.flexDirection.toLowerCase().startsWith('column'))
      return _flow(box, x, width);
    final geometry = CraftHtmlBoxGeometry.resolve(box.style, x, width);
    final start = _cursor;
    _cursor += geometry.marginTop + geometry.paddingTop;
    if (!box.style.hasJustifyContent && !box.style.flexWrap) {
      final childWidth =
          (geometry.contentWidth - box.style.gap * (box.children.length - 1)) /
              box.children.length;
      var bottom = _cursor;
      for (var index = 0; index < box.children.length; index++) {
        _cursor = start + geometry.marginTop + geometry.paddingTop;
        _layout(box.children[index],
            geometry.x + index * (childWidth + box.style.gap), childWidth);
        if (_cursor > bottom) bottom = _cursor;
      }
      _cursor = bottom + box.style.text.fontSize * .35 + geometry.paddingBottom;
      _addDecoration(box, geometry, start + geometry.marginTop, _cursor);
      _cursor += geometry.marginBottom;
      return _cursor - start;
    }
    final rows = CraftHtmlLayoutPlan.flexRows(box.children,
        availableWidth: geometry.contentWidth,
        widthOf: (child) => _intrinsicWidth(child, geometry.contentWidth),
        gap: box.style.gap,
        wrap: box.style.flexWrap);
    for (final row in rows) {
      final widths = [
        for (final child in row.items)
          _intrinsicWidth(child, geometry.contentWidth)
      ];
      final contentWidth = widths.fold<double>(0, (sum, value) => sum + value) +
          box.style.gap * (row.items.length - 1);
      final remaining = (geometry.contentWidth - contentWidth)
          .clamp(0.0, double.infinity)
          .toDouble();
      final initial = box.style.justifyContent == CraftHtmlJustifyContent.center
          ? remaining / 2
          : box.style.justifyContent == CraftHtmlJustifyContent.end
              ? remaining
              : 0.0;
      final gap =
          box.style.justifyContent == CraftHtmlJustifyContent.spaceBetween &&
                  row.items.length > 1
              ? box.style.gap + remaining / (row.items.length - 1)
              : box.style.gap;
      final rowStart = _cursor;
      var bottom = rowStart;
      var offset = initial;
      for (var index = 0; index < row.items.length; index++) {
        _cursor = rowStart;
        _layout(row.items[index], geometry.x + offset, widths[index]);
        if (_cursor > bottom) bottom = _cursor;
        offset += widths[index] + gap;
      }
      _cursor = bottom + box.style.gap;
    }
    _cursor += box.style.text.fontSize * .35 + geometry.paddingBottom;
    _addDecoration(box, geometry, start + geometry.marginTop, _cursor);
    _cursor += geometry.marginBottom;
    return _cursor - start;
  }

  double _intrinsicWidth(CraftHtmlBox box, double maximum) {
    if (!box.style.width.isAuto) {
      return box.style.width.resolve(maximum).clamp(1.0, maximum).toDouble();
    }
    if (box.isText) {
      return (box.text!.length * box.style.text.fontSize * .52)
          .clamp(1.0, maximum)
          .toDouble();
    }
    if (box.children.isEmpty) return 1.0;
    var intrinsic = 0.0;
    for (final child in box.children) {
      final childWidth = _intrinsicWidth(child, maximum);
      if (box.style.display == CraftHtmlDisplay.flex &&
          !box.style.flexDirection.toLowerCase().startsWith('column')) {
        intrinsic += childWidth;
      } else if (childWidth > intrinsic) {
        intrinsic = childWidth;
      }
    }
    if (box.style.display == CraftHtmlDisplay.flex && box.children.length > 1) {
      intrinsic += box.style.gap * (box.children.length - 1);
    }
    return intrinsic.clamp(1.0, maximum).toDouble();
  }

  double _grid(CraftHtmlBox box, double x, double width) {
    final geometry = CraftHtmlBoxGeometry.resolve(box.style, x, width);
    final widths = CraftHtmlLayoutPlan.gridTrackWidths(
        box.style.gridTemplateColumns, geometry.contentWidth,
        gap: box.style.gap);
    final columns = widths.length;
    final rows = CraftHtmlLayoutPlan.grid(box.children, columns);
    final start = _cursor;
    _cursor += geometry.marginTop + geometry.paddingTop;
    for (final row in rows) {
      final rowStart = _cursor;
      var bottom = rowStart;
      var offset = 0.0;
      for (var column = 0; column < row.items.length; column++) {
        _cursor = rowStart;
        _layout(row.items[column], geometry.x + offset, widths[column]);
        if (_cursor > bottom) bottom = _cursor;
        offset += widths[column] + box.style.gap;
      }
      _cursor = bottom + box.style.gap;
    }
    _cursor += box.style.text.fontSize * .35 + geometry.paddingBottom;
    _addDecoration(box, geometry, start + geometry.marginTop, _cursor);
    _cursor += geometry.marginBottom;
    return _cursor - start;
  }

  /// Lays out semantic table rows and cells in equal physical columns.
  /// Cell content still passes through the ordinary flow routine, preserving
  /// its own wrapping and inherited text style while every cell in a row
  /// shares the same starting baseline.
  double _table(CraftHtmlBox box, double x, double width) {
    final rows = box.children
        .where((child) => child.role == CraftHtmlBoxRole.tableRow)
        .toList(growable: false);
    if (rows.isEmpty) return 0;
    var columns = 0;
    for (final row in rows) {
      if (row.children.length > columns) columns = row.children.length;
    }
    if (columns == 0) return 0;
    final geometry = CraftHtmlBoxGeometry.resolve(box.style, x, width);
    final columnWidth =
        (geometry.contentWidth - box.style.gap * (columns - 1)) / columns;
    final start = _cursor;
    _cursor += geometry.marginTop + geometry.paddingTop;
    for (final row in rows) {
      final rowStart = _cursor;
      var bottom = rowStart;
      var offset = 0.0;
      for (final cell in row.children) {
        _cursor = rowStart;
        _layout(cell, geometry.x + offset, columnWidth);
        if (_cursor > bottom) bottom = _cursor;
        offset += columnWidth + box.style.gap;
      }
      _cursor = bottom + box.style.gap;
    }
    _cursor += box.style.text.fontSize * .35 + geometry.paddingBottom;
    _addDecoration(box, geometry, start + geometry.marginTop, _cursor);
    _cursor += geometry.marginBottom;
    return _cursor - start;
  }

  void _addDecoration(CraftHtmlBox box, CraftHtmlBoxGeometry geometry,
      double top, double bottom) {
    if (box.style.backgroundColor == null && box.style.border == null) return;
    final height = bottom - top;
    if (height <= 0 || geometry.paintWidth <= 0) return;
    _decorations.add(CraftHtmlBoxDecoration(
      x: geometry.paintX,
      top: top,
      width: geometry.paintWidth,
      height: height,
      backgroundColor: box.style.backgroundColor,
      border: box.style.border,
    ));
  }

  double _paragraph(
      String value, CraftHtmlTextStyle style, double x, double width,
      {String? linkTarget}) {
    final lineHeight = style.fontSize * 1.35;
    final limit = (width / (style.fontSize * .52)).floor().clamp(1, 10000);
    for (final line in _wrap(value, limit)) {
      _cursor += lineHeight;
      _fragments.add(CraftHtmlTextFragment(line, style, x, _cursor,
          linkTarget: linkTarget));
    }
    return lineHeight;
  }

  Iterable<String> _wrap(String value, int limit) sync* {
    for (final forcedLine in value.split('\n')) {
      var line = '';
      for (final word in CraftHtmlText.words(forcedLine)) {
        if (word.isEmpty) continue;
        final candidate = line.isEmpty ? word : '$line $word';
        if (candidate.length > limit && line.isNotEmpty) {
          yield line;
          line = word;
        } else {
          line = candidate;
        }
      }
      if (line.isNotEmpty) yield line;
    }
  }
}

class _InlineWord {
  final String text;
  final CraftHtmlTextStyle style;
  final double offset;
  final String? linkTarget;
  const _InlineWord(this.text, this.style, this.offset, this.linkTarget);
}
