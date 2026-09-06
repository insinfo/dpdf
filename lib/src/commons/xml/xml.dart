/// Small SDK-only XML DOM for PDF metadata and XFA packets.
/// DTDs are rejected: no external resources or custom entities are resolved.
/// This is not a validating XML processor or an XML canonicalization engine.
library;

String _escape(String value, {bool attribute = false}) {
  var result = value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  if (attribute)
    result = result
        .replaceAll('"', '&quot;')
        .replaceAll('\t', '&#9;')
        .replaceAll('\n', '&#10;')
        .replaceAll('\r', '&#13;');
  return result;
}

class XmlName {
  final String qualified;
  final String? namespaceUri;
  XmlName(this.qualified, [this.namespaceUri]);
  String get local => qualified.split(':').last;
  String? get prefix =>
      qualified.contains(':') ? qualified.split(':').first : null;
}

abstract class XmlNode {
  String toXmlString({bool pretty = false, String indent = '  '});
  String get innerText => '';
}

class XmlText extends XmlNode {
  final String value;
  XmlText(this.value);
  @override
  String get innerText => value;
  @override
  String toXmlString({bool pretty = false, String indent = '  '}) =>
      _escape(value);
}

class XmlCDATA extends XmlText {
  XmlCDATA(super.value);
  @override
  String toXmlString({bool pretty = false, String indent = '  '}) =>
      '<![CDATA[${value.replaceAll(']]>', ']]]]><![CDATA[>')}]]>';
}

class XmlComment extends XmlNode {
  final String value;
  XmlComment(this.value);
  @override
  String toXmlString({bool pretty = false, String indent = '  '}) =>
      '<!--$value-->';
}

class XmlProcessing extends XmlNode {
  final String value;
  XmlProcessing(this.value);
  @override
  String toXmlString({bool pretty = false, String indent = '  '}) =>
      '<?$value?>';
}

Iterable<XmlElement> _find(
    List<XmlNode> children, String name, String? namespace) sync* {
  for (final child in children.whereType<XmlElement>()) {
    if ((namespace == null
        ? child.name.qualified == name
        : child.name.local == name && child.name.namespaceUri == namespace))
      yield child;
    yield* _find(child.children, name, namespace);
  }
}

class XmlElement extends XmlNode {
  Map<String, String> _namespaceBindings = {};
  final XmlName name;
  final Map<String, String> attributes;
  final List<XmlNode> children;
  XmlElement(this.name,
      [Map<String, String>? attributes, List<XmlNode>? children])
      : attributes = attributes ?? {},
        children = children ?? [];
  String? getAttribute(String name) => attributes[name];
  void setAttribute(String name, String value) => attributes[name] = value;
  Iterable<XmlElement> findAllElements(String name, {String? namespace}) =>
      _find(children, name, namespace);
  @override
  String get innerText => children.map((n) => n.innerText).join();
  set innerText(String text) {
    children
      ..clear()
      ..add(XmlText(text));
  }

  @override
  String toXmlString({bool pretty = false, String indent = '  '}) {
    final serializedAttributes = <String, String>{
      for (final entry in _namespaceBindings.entries)
        if (entry.key != 'xml')
          (entry.key.isEmpty ? 'xmlns' : 'xmlns:${entry.key}'): entry.value,
      ...attributes,
    };
    final attrs = serializedAttributes.entries
        .map((e) => ' ${e.key}="${_escape(e.value, attribute: true)}"')
        .join();
    if (children.isEmpty) return '<${name.qualified}$attrs/>';
    return '<${name.qualified}$attrs>${children.map((n) => n.toXmlString()).join()}</${name.qualified}>';
  }
}

class XmlDocument extends XmlNode {
  final List<XmlNode> children;
  XmlDocument(this.children);
  factory XmlDocument.parse(String source) => _Parser(source).parse();
  XmlElement get rootElement => children.whereType<XmlElement>().single;
  Iterable<XmlElement> findAllElements(String name, {String? namespace}) =>
      _find(children, name, namespace);
  @override
  String toXmlString({bool pretty = false, String indent = '  '}) =>
      children.map((n) => n.toXmlString()).join();
}

class _Parser {
  final String source;
  int offset = 0;
  int nodes = 0;
  _Parser(String source)
      : source = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  Never fail(String message) => throw FormatException(message, source, offset);
  bool starts(String value) => source.startsWith(value, offset);
  void space() {
    while (offset < source.length && ' \t\n\r'.contains(source[offset])) {
      offset++;
    }
  }

  String name() {
    final start = offset;
    bool needsStart = true;
    bool hasPrefix = false;
    while (offset < source.length) {
      final code = _codePointAt(offset);
      if (needsStart) {
        if (!_nameStart(code)) fail('Expected XML name');
        needsStart = false;
      } else if (code == 0x3a) {
        if (hasPrefix) fail('Invalid qualified XML name');
        hasPrefix = true;
        needsStart = true;
      } else if (!_nameChar(code)) {
        break;
      }
      offset += code > 0xffff ? 2 : 1;
    }
    if (needsStart) fail('Expected XML name');
    return source.substring(start, offset);
  }

  int _codePointAt(int index) {
    final first = source.codeUnitAt(index);
    if (first < 0xd800 || first > 0xdbff || index + 1 == source.length) {
      return first;
    }
    final second = source.codeUnitAt(index + 1);
    if (second < 0xdc00 || second > 0xdfff) return first;
    return 0x10000 + ((first - 0xd800) << 10) + second - 0xdc00;
  }

  // XML 1.0 Fifth Edition, productions [4]/[4a], with colon handled as
  // the QName separator rather than as part of either NCName component.
  // https://www.w3.org/TR/xml/#NT-NameStartChar
  bool _nameStart(int c) =>
      c == 0x5f ||
      c >= 0x41 && c <= 0x5a ||
      c >= 0x61 && c <= 0x7a ||
      c >= 0xc0 && c <= 0xd6 ||
      c >= 0xd8 && c <= 0xf6 ||
      c >= 0xf8 && c <= 0x2ff ||
      c >= 0x370 && c <= 0x37d ||
      c >= 0x37f && c <= 0x1fff ||
      c >= 0x200c && c <= 0x200d ||
      c >= 0x2070 && c <= 0x218f ||
      c >= 0x2c00 && c <= 0x2fef ||
      c >= 0x3001 && c <= 0xd7ff ||
      c >= 0xf900 && c <= 0xfdcf ||
      c >= 0xfdf0 && c <= 0xfffd ||
      c >= 0x10000 && c <= 0xeffff;

  bool _nameChar(int c) =>
      _nameStart(c) ||
      c == 0x2d ||
      c == 0x2e ||
      c >= 0x30 && c <= 0x39 ||
      c == 0xb7 ||
      c >= 0x300 && c <= 0x36f ||
      c >= 0x203f && c <= 0x2040;

  String until(String end) {
    final index = source.indexOf(end, offset);
    if (index < 0) fail('Unterminated XML construct');
    final value = source.substring(offset, index);
    offset = index + end.length;
    return value;
  }

  bool validChar(int c) =>
      c == 9 ||
      c == 10 ||
      c == 13 ||
      c >= 32 && c <= 0xd7ff ||
      c >= 0xe000 && c <= 0xfffd ||
      c >= 0x10000 && c <= 0x10ffff;
  String decode(String text) {
    final out = StringBuffer();
    var pos = 0;
    while (pos < text.length) {
      if (text[pos] != '&') {
        out.write(text[pos++]);
        continue;
      }
      final end = text.indexOf(';', pos);
      if (end < 0) fail('Unterminated XML entity');
      final entity = text.substring(pos + 1, end);
      const standard = {
        'amp': '&',
        'lt': '<',
        'gt': '>',
        'quot': '"',
        'apos': "'"
      };
      if (standard.containsKey(entity)) {
        out.write(standard[entity]);
      } else if (entity.startsWith('#')) {
        final hex = entity.startsWith('#x');
        final number =
            int.tryParse(entity.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
        if (number == null || !validChar(number))
          fail('Invalid XML character reference');
        out.writeCharCode(number);
      } else {
        fail('Unsupported XML entity');
      }
      pos = end + 1;
    }
    return out.toString();
  }

  XmlDocument parse() {
    if (source.runes.any((c) => !validChar(c))) fail('Invalid XML character');
    if (starts('\ufeff')) offset++;
    final children = <XmlNode>[];
    while (offset < source.length) {
      children.add(node({'xml': 'http://www.w3.org/XML/1998/namespace'}, 0));
    }
    if (children.whereType<XmlElement>().length != 1 ||
        children
            .whereType<XmlText>()
            .any((n) => n is XmlCDATA || n.value.trim().isNotEmpty))
      fail('Expected one XML document element');
    return XmlDocument(children);
  }

  XmlNode node(Map<String, String> inherited, int depth) {
    if (++nodes > 1000000 || depth > 256) fail('XML complexity limit exceeded');
    if (starts('<!--')) {
      offset += 4;
      final text = until('-->');
      if (text.contains('--') || text.endsWith('-'))
        fail('Invalid XML comment');
      return XmlComment(text);
    }
    if (starts('<?')) {
      offset += 2;
      return XmlProcessing(until('?>'));
    }
    if (starts('<![CDATA[')) {
      offset += 9;
      return XmlCDATA(until(']]>'));
    }
    if (starts('<!')) fail('DTD and declarations are unsupported');
    if (!starts('<')) {
      final end = source.indexOf('<', offset);
      final raw = source.substring(offset, end < 0 ? source.length : end);
      offset += raw.length;
      if (raw.contains(']]>')) fail('CDATA terminator in text');
      return XmlText(decode(raw));
    }
    offset++;
    final tag = name();
    final attrs = <String, String>{};
    while (true) {
      final before = offset;
      space();
      if (starts('>') || starts('/>')) break;
      if (before == offset) fail('Expected space before attribute');
      final key = name();
      space();
      if (!starts('=')) fail('Expected attribute value');
      offset++;
      space();
      if (offset >= source.length || !'"\''.contains(source[offset]))
        fail('Expected quoted attribute');
      final quote = source[offset++];
      final raw = until(quote);
      if (raw.contains('<') || attrs.containsKey(key))
        fail('Invalid or duplicate XML attribute');
      attrs[key] = decode(raw.replaceAll(RegExp(r'[\t\n\r]'), ' '));
    }
    final namespaces = {...inherited};
    for (final entry in attrs.entries) {
      if (entry.key == 'xmlns:xmlns' ||
          ((entry.key == 'xmlns' || entry.key.startsWith('xmlns:')) &&
              entry.value == 'http://www.w3.org/2000/xmlns/') ||
          (entry.key == 'xmlns:xml' &&
              entry.value != 'http://www.w3.org/XML/1998/namespace') ||
          (entry.key != 'xmlns:xml' &&
              (entry.key == 'xmlns' || entry.key.startsWith('xmlns:')) &&
              entry.value == 'http://www.w3.org/XML/1998/namespace')) {
        fail('Invalid reserved namespace binding');
      }
      if (entry.key == 'xmlns')
        namespaces[''] = entry.value;
      else if (entry.key.startsWith('xmlns:'))
        namespaces[entry.key.substring(6)] = entry.value;
    }
    String? resolve(String key, bool attribute) {
      final parts = key.split(':');
      if (parts.length == 1) return attribute ? null : namespaces[''];
      if (parts.first == 'xmlns') return 'http://www.w3.org/2000/xmlns/';
      final uri = namespaces[parts.first];
      if (uri == null || uri.isEmpty) fail('Undeclared XML namespace prefix');
      return uri;
    }

    final expanded = <String>{};
    for (final key in attrs.keys) {
      if (!expanded.add('${resolve(key, true)}|${key.split(':').last}'))
        fail('Duplicate expanded attribute');
    }
    final element = XmlElement(XmlName(tag, resolve(tag, false)), attrs);
    element._namespaceBindings = namespaces;
    if (starts('/>')) {
      offset += 2;
      return element;
    }
    offset++;
    while (!starts('</')) {
      if (offset >= source.length) fail('Unclosed XML element');
      element.children.add(node(namespaces, depth + 1));
    }
    offset += 2;
    if (name() != tag) fail('Mismatched XML closing element');
    space();
    if (!starts('>')) fail('Expected closing bracket');
    offset++;
    return element;
  }
}
