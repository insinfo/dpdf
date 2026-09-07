import 'package:html/dom.dart' as dom;

/// Stateful marker sequence for one direct HTML list level.
///
/// A fresh context is created for every `<ol>` or `<ul>`, so nested lists do
/// not consume their parent's counter. Integer attributes use `int.tryParse`,
/// which keeps malformed input inert and requires no regular expressions.
class CraftHtmlListContext {
  final bool ordered;
  final bool reversed;
  int _next;

  CraftHtmlListContext._(this.ordered, this.reversed, this._next);

  factory CraftHtmlListContext.fromElement(dom.Element list) {
    final tag = list.localName?.toLowerCase();
    final ordered = tag == 'ol';
    if (!ordered) return CraftHtmlListContext._(false, false, 0);
    final reversed = list.attributes.containsKey('reversed');
    final itemCount = list.children
        .where((child) => child.localName?.toLowerCase() == 'li')
        .length;
    final declaredStart = _integer(list.attributes['start']);
    final start = declaredStart ?? (reversed ? itemCount : 1);
    return CraftHtmlListContext._(true, reversed, start);
  }

  String markerFor(dom.Element item) {
    if (!ordered) return '• ';
    final declaredValue = _integer(item.attributes['value']);
    if (declaredValue != null) _next = declaredValue;
    final current = _next;
    _next += reversed ? -1 : 1;
    return '$current. ';
  }

  static int? _integer(String? source) {
    if (source == null) return null;
    return int.tryParse(source.trim());
  }
}
