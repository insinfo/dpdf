import 'package:html/dom.dart' as dom;

import '../css/css_values.dart';
import 'html_data_image.dart';
import '../css/css_border.dart';
import '../css/css_color.dart';
import '../css/html_style_sheet.dart';
import '../model/html_box.dart';
import '../model/html_text.dart';
import 'html_list_context.dart';

/// Turns a parsed HTML DOM into a platform-neutral, normalized box tree.
class HtmlBoxBuilder {
  final HtmlStyleSheet styleSheet;
  final double baseFontSize;

  const HtmlBoxBuilder(this.styleSheet, this.baseFontSize);

  List<HtmlBox> build(Iterable<dom.Node> nodes,
      [HtmlTextStyle? inherited,
      String? inheritedLink,
      HtmlListContext? listContext]) {
    final textStyle = inherited ?? HtmlTextStyle(baseFontSize);
    final result = <HtmlBox>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        final value = HtmlText.collapseWhitespace(node.data);
        if (value.trim().isNotEmpty) {
          result.add(_text(value, textStyle, linkTarget: inheritedLink));
        }
        continue;
      }
      if (node is! dom.Element) continue;
      final tag = node.localName?.toLowerCase() ?? '';
      if (const {'script', 'style', 'noscript', 'template'}.contains(tag)) {
        continue;
      }
      final declarations = styleSheet.resolve(node);
      final style = _styleFor(tag, declarations, textStyle);
      final href = tag == 'a' ? node.attributes['href']?.trim() : null;
      final linkTarget = href == null || href.isEmpty ? inheritedLink : href;
      if (style.display == HtmlDisplay.none) continue;
      if (tag == 'br') {
        result.add(_text('\n', style.text, linkTarget: linkTarget));
      } else if (tag == 'img') {
        final alternative = node.attributes['alt'];
        final image = HtmlDataImage.tryParse(node.attributes['src'],
            width: node.attributes['width'], height: node.attributes['height']);
        if (image != null) {
          result.add(HtmlBox(style: style, image: image));
        } else if (alternative != null && alternative.isNotEmpty) {
          result.add(_text(alternative, style.text, linkTarget: linkTarget));
        }
      } else if (tag == 'table') {
        result.add(_table(node, style, linkTarget));
      } else {
        final childListContext = tag == 'ol' || tag == 'ul'
            ? HtmlListContext.fromElement(node)
            : null;
        var children =
            build(node.nodes, style.text, linkTarget, childListContext);
        if (tag == 'li' && children.isNotEmpty) {
          children = [
            _text(listContext?.markerFor(node) ?? '• ', style.text,
                linkTarget: linkTarget),
            ...children
          ];
        }
        result.add(HtmlBox(style: style, children: children));
      }
    }
    return result;
  }

  HtmlBox _table(dom.Element table, HtmlBoxStyle style, String? linkTarget) {
    final rows = <HtmlBox>[];
    for (final row in _rows(table)) {
      final rowStyle = _styleFor('tr', styleSheet.resolve(row), style.text);
      final cells = <HtmlBox>[];
      for (final cell in row.children) {
        final tag = cell.localName?.toLowerCase();
        if (tag != 'td' && tag != 'th') continue;
        final cellStyle =
            _styleFor(tag!, styleSheet.resolve(cell), rowStyle.text);
        final children = build(cell.nodes, cellStyle.text, linkTarget);
        if (children.isEmpty) continue;
        cells.add(HtmlBox(
            style: cellStyle,
            role: tag == 'th'
                ? HtmlBoxRole.tableHeaderCell
                : HtmlBoxRole.tableCell,
            children: children));
      }
      if (cells.isNotEmpty) {
        rows.add(HtmlBox(
            style: rowStyle, role: HtmlBoxRole.tableRow, children: cells));
      }
    }
    return HtmlBox(style: style, role: HtmlBoxRole.table, children: rows);
  }

  Iterable<dom.Element> _rows(dom.Element table) sync* {
    for (final child in table.children) {
      final tag = child.localName?.toLowerCase();
      if (tag == 'tr') {
        yield child;
      } else if (tag == 'thead' || tag == 'tbody' || tag == 'tfoot') {
        for (final row in child.children) {
          if (row.localName?.toLowerCase() == 'tr') yield row;
        }
      }
    }
  }

  HtmlBox _text(String value, HtmlTextStyle style, {String? linkTarget}) =>
      HtmlBox(
          style: HtmlBoxStyle(display: HtmlDisplay.inline, text: style),
          text: value,
          linkTarget: linkTarget);

  HtmlBoxStyle _styleFor(
      String tag, Map<String, String> css, HtmlTextStyle inherited) {
    final headingScale = tag == 'h1'
        ? 2.0
        : tag == 'h2'
            ? 1.6
            : tag == 'h3'
                ? 1.35
                : tag.startsWith('h')
                    ? 1.15
                    : 1.0;
    final fontSize =
        _fontSize(css['font-size'], inherited.fontSize) * headingScale;
    final text = HtmlTextStyle(fontSize,
        fontFamily: css['font-family'] ?? inherited.fontFamily,
        bold: _fontWeight(
            css['font-weight'],
            inherited.bold ||
                tag == 'strong' ||
                tag == 'b' ||
                tag == 'th' ||
                tag.startsWith('h')),
        italic: _fontStyle(
            css['font-style'], inherited.italic || tag == 'em' || tag == 'i'),
        color: CssColors.parse(css['color']) ?? inherited.color);
    final declared = css['display']?.toLowerCase();
    final display = declared == 'flex'
        ? HtmlDisplay.flex
        : declared == 'grid'
            ? HtmlDisplay.grid
            : declared == 'none'
                ? HtmlDisplay.none
                : _blockTags.contains(tag)
                    ? HtmlDisplay.block
                    : HtmlDisplay.inline;
    return HtmlBoxStyle(
      display: display,
      text: text,
      flexDirection: css['flex-direction'] ?? 'row',
      flexWrap: css['flex-wrap']?.trim().toLowerCase() == 'wrap',
      justifyContent: _justifyContent(css['justify-content']),
      hasJustifyContent: css.containsKey('justify-content'),
      gridTemplateColumns: css['grid-template-columns'],
      gap: _length(css['gap']),
      width: CssValues.lengthValue(css['width']),
      margin: _edges(css, 'margin'),
      padding: _edges(css, 'padding'),
      textAlign: _textAlign(css['text-align']),
      backgroundColor: CssColors.parse(css['background-color']),
      border: _border(css),
    );
  }

  HtmlBorder? _border(Map<String, String> css) {
    final value = CssBorders.parse(css);
    return value == null ? null : HtmlBorder(value.width, value.color);
  }

  CssEdges _edges(Map<String, String> css, String name) {
    var edges = CssValues.edges(css[name]);
    return edges.override(
      top: _overrideLength(css, '$name-top'),
      right: _overrideLength(css, '$name-right'),
      bottom: _overrideLength(css, '$name-bottom'),
      left: _overrideLength(css, '$name-left'),
    );
  }

  CssLength? _overrideLength(Map<String, String> css, String name) =>
      css.containsKey(name) ? CssValues.lengthValue(css[name]) : null;

  HtmlTextAlign _textAlign(String? source) =>
      switch (source?.trim().toLowerCase()) {
        'center' => HtmlTextAlign.center,
        'right' || 'end' => HtmlTextAlign.end,
        'justify' => HtmlTextAlign.justify,
        _ => HtmlTextAlign.start,
      };

  double _fontSize(String? source, double fallback) {
    final value = CssValues.length(source, fallback: fallback);
    return value <= 0 ? fallback : value;
  }

  double _length(String? source) {
    return CssValues.length(source);
  }

  bool _fontWeight(String? source, bool fallback) {
    final value = source?.trim().toLowerCase();
    if (value == null || value.isEmpty) return fallback;
    if (value == 'bold' || value == 'bolder') return true;
    if (value == 'normal' || value == 'lighter') return false;
    final numeric = int.tryParse(value);
    return numeric == null ? fallback : numeric >= 600;
  }

  bool _fontStyle(String? source, bool fallback) {
    switch (source?.trim().toLowerCase()) {
      case 'italic':
      case 'oblique':
        return true;
      case 'normal':
        return false;
      default:
        return fallback;
    }
  }

  HtmlJustifyContent _justifyContent(String? source) {
    switch (source?.trim().toLowerCase()) {
      case 'center':
        return HtmlJustifyContent.center;
      case 'end':
      case 'flex-end':
        return HtmlJustifyContent.end;
      case 'space-between':
        return HtmlJustifyContent.spaceBetween;
      case 'start':
      case 'flex-start':
      default:
        return HtmlJustifyContent.start;
    }
  }
}

const _blockTags = {
  'html',
  'body',
  'p',
  'div',
  'section',
  'article',
  'header',
  'footer',
  'blockquote',
  'pre',
  'ul',
  'ol',
  'li',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6'
};
