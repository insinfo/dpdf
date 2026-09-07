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
class CraftHtmlBoxBuilder {
  final CraftHtmlStyleSheet styleSheet;
  final double baseFontSize;

  const CraftHtmlBoxBuilder(this.styleSheet, this.baseFontSize);

  List<CraftHtmlBox> build(Iterable<dom.Node> nodes,
      [CraftHtmlTextStyle? inherited,
      String? inheritedLink,
      CraftHtmlListContext? listContext]) {
    final textStyle = inherited ?? CraftHtmlTextStyle(baseFontSize);
    final result = <CraftHtmlBox>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        final value = CraftHtmlText.collapseWhitespace(node.data);
        if (value.trim().isNotEmpty) {
          result.add(_text(value, textStyle, linkTarget: inheritedLink));
        }
        continue;
      }
      if (node is! dom.Element) continue;
      final tag = node.localName?.toLowerCase() ?? '';
      if (const {'script', 'style', 'noscript', 'template'}.contains(tag))
        continue;
      final declarations = styleSheet.resolve(node);
      final style = _styleFor(tag, declarations, textStyle);
      final href = tag == 'a' ? node.attributes['href']?.trim() : null;
      final linkTarget = href == null || href.isEmpty ? inheritedLink : href;
      if (style.display == CraftHtmlDisplay.none) continue;
      if (tag == 'br') {
        result.add(_text('\n', style.text, linkTarget: linkTarget));
      } else if (tag == 'img') {
        final alternative = node.attributes['alt'];
        final image = CraftHtmlDataImage.tryParse(node.attributes['src'],
            width: node.attributes['width'], height: node.attributes['height']);
        if (image != null) {
          result.add(CraftHtmlBox(style: style, image: image));
        } else if (alternative != null && alternative.isNotEmpty) {
          result.add(_text(alternative, style.text, linkTarget: linkTarget));
        }
      } else if (tag == 'table') {
        result.add(_table(node, style, linkTarget));
      } else {
        final childListContext = tag == 'ol' || tag == 'ul'
            ? CraftHtmlListContext.fromElement(node)
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
        result.add(CraftHtmlBox(style: style, children: children));
      }
    }
    return result;
  }

  CraftHtmlBox _table(
      dom.Element table, CraftHtmlBoxStyle style, String? linkTarget) {
    final rows = <CraftHtmlBox>[];
    for (final row in _rows(table)) {
      final rowStyle = _styleFor('tr', styleSheet.resolve(row), style.text);
      final cells = <CraftHtmlBox>[];
      for (final cell in row.children) {
        final tag = cell.localName?.toLowerCase();
        if (tag != 'td' && tag != 'th') continue;
        final cellStyle =
            _styleFor(tag!, styleSheet.resolve(cell), rowStyle.text);
        final children = build(cell.nodes, cellStyle.text, linkTarget);
        if (children.isEmpty) continue;
        cells.add(CraftHtmlBox(
            style: cellStyle,
            role: tag == 'th'
                ? CraftHtmlBoxRole.tableHeaderCell
                : CraftHtmlBoxRole.tableCell,
            children: children));
      }
      if (cells.isNotEmpty) {
        rows.add(CraftHtmlBox(
            style: rowStyle, role: CraftHtmlBoxRole.tableRow, children: cells));
      }
    }
    return CraftHtmlBox(
        style: style, role: CraftHtmlBoxRole.table, children: rows);
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

  CraftHtmlBox _text(String value, CraftHtmlTextStyle style,
          {String? linkTarget}) =>
      CraftHtmlBox(
          style:
              CraftHtmlBoxStyle(display: CraftHtmlDisplay.inline, text: style),
          text: value,
          linkTarget: linkTarget);

  CraftHtmlBoxStyle _styleFor(
      String tag, Map<String, String> css, CraftHtmlTextStyle inherited) {
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
    final text = CraftHtmlTextStyle(fontSize,
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
        color: CraftCssColors.parse(css['color']) ?? inherited.color);
    final declared = css['display']?.toLowerCase();
    final display = declared == 'flex'
        ? CraftHtmlDisplay.flex
        : declared == 'grid'
            ? CraftHtmlDisplay.grid
            : declared == 'none'
                ? CraftHtmlDisplay.none
                : _blockTags.contains(tag)
                    ? CraftHtmlDisplay.block
                    : CraftHtmlDisplay.inline;
    return CraftHtmlBoxStyle(
      display: display,
      text: text,
      flexDirection: css['flex-direction'] ?? 'row',
      flexWrap: css['flex-wrap']?.trim().toLowerCase() == 'wrap',
      justifyContent: _justifyContent(css['justify-content']),
      hasJustifyContent: css.containsKey('justify-content'),
      gridTemplateColumns: css['grid-template-columns'],
      gap: _length(css['gap']),
      width: CraftCssValues.lengthValue(css['width']),
      margin: _edges(css, 'margin'),
      padding: _edges(css, 'padding'),
      textAlign: _textAlign(css['text-align']),
      backgroundColor: CraftCssColors.parse(css['background-color']),
      border: _border(css),
    );
  }

  CraftHtmlBorder? _border(Map<String, String> css) {
    final value = CraftCssBorders.parse(css);
    return value == null ? null : CraftHtmlBorder(value.width, value.color);
  }

  CraftCssEdges _edges(Map<String, String> css, String name) {
    var edges = CraftCssValues.edges(css[name]);
    return edges.override(
      top: _overrideLength(css, '$name-top'),
      right: _overrideLength(css, '$name-right'),
      bottom: _overrideLength(css, '$name-bottom'),
      left: _overrideLength(css, '$name-left'),
    );
  }

  CraftCssLength? _overrideLength(Map<String, String> css, String name) =>
      css.containsKey(name) ? CraftCssValues.lengthValue(css[name]) : null;

  CraftHtmlTextAlign _textAlign(String? source) =>
      switch (source?.trim().toLowerCase()) {
        'center' => CraftHtmlTextAlign.center,
        'right' || 'end' => CraftHtmlTextAlign.end,
        'justify' => CraftHtmlTextAlign.justify,
        _ => CraftHtmlTextAlign.start,
      };

  double _fontSize(String? source, double fallback) {
    final value = CraftCssValues.length(source, fallback: fallback);
    return value <= 0 ? fallback : value;
  }

  double _length(String? source) {
    return CraftCssValues.length(source);
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

  CraftHtmlJustifyContent _justifyContent(String? source) {
    switch (source?.trim().toLowerCase()) {
      case 'center':
        return CraftHtmlJustifyContent.center;
      case 'end':
      case 'flex-end':
        return CraftHtmlJustifyContent.end;
      case 'space-between':
        return CraftHtmlJustifyContent.spaceBetween;
      case 'start':
      case 'flex-start':
      default:
        return CraftHtmlJustifyContent.start;
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
