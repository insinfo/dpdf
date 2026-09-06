import 'dart:convert';
import 'package:xml/xml.dart' as xml;
import 'xmp_const.dart';

class XMPMeta {
  xml.XmlDocument _doc;
  xml.XmlElement? _rdfDescription;

  XMPMeta(this._doc) {
    _init();
  }

  void _init() {
    // Find rdf:Description
    const rdfNs = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';

    var rdf = _doc.findAllElements('RDF', namespace: rdfNs).firstOrNull ??
        _doc.findAllElements('rdf:RDF').firstOrNull;

    if (rdf != null) {
      _rdfDescription =
          rdf.findAllElements('Description', namespace: rdfNs).firstOrNull ??
              rdf.findAllElements('rdf:Description').firstOrNull;
      if (_rdfDescription == null) {
        _rdfDescription = xml.XmlElement(xml.XmlName('rdf:Description'));
        _rdfDescription!.setAttribute('rdf:about', '');
        rdf.children.add(_rdfDescription!);
      }
    }
  }

  static XMPMeta create() {
    final builder = xml.XmlBuilder();
    builder.processing('xpacket', 'begin="" id="W5M0MpCehiHzreSzNTczkc9d"');
    builder.element('x:xmpmeta', namespaces: {'adobe:ns:meta/': 'x'}, nest: () {
      builder.element('rdf:RDF',
          namespaces: {'http://www.w3.org/1999/02/22-rdf-syntax-ns#': 'rdf'},
          nest: () {
        builder.element('rdf:Description',
            attributes: {'rdf:about': ''}, nest: () {});
      });
    });
    builder.processing('xpacket', 'end="w"');
    return XMPMeta(builder.buildDocument());
  }

  void setObjectName(String name) {}

  void setProperty(String schemaNS, String propName, dynamic propValue) {
    if (_rdfDescription == null) return;

    String? prefix;
    if (schemaNS == XMPConst.NS_DC)
      prefix = 'dc';
    else if (schemaNS == XMPConst.NS_XMP)
      prefix = 'xmp';
    else if (schemaNS == XMPConst.NS_PDF) prefix = 'pdf';

    if (prefix != null) {
      if (_rdfDescription!.getAttribute('xmlns:$prefix') == null) {
        _rdfDescription!.setAttribute('xmlns:$prefix', schemaNS);
      }

      final pattern = '$prefix:$propName';

      _rdfDescription!.children.removeWhere((node) =>
          node is xml.XmlElement &&
          (node.name.qualified == pattern ||
              (node.name.local == propName &&
                  node.name.namespaceUri == schemaNS)));

      if (propValue != null) {
        final el = xml.XmlElement(xml.XmlName(pattern));
        el.innerText = propValue.toString();
        _rdfDescription!.children.add(el);
      }
    }
  }

  String? getPropertyString(String schemaNS, String propName) {
    if (_rdfDescription == null) return null;
    String? prefix;
    if (schemaNS == XMPConst.NS_DC)
      prefix = 'dc';
    else if (schemaNS == XMPConst.NS_XMP)
      prefix = 'xmp';
    else if (schemaNS == XMPConst.NS_PDF) prefix = 'pdf';

    if (prefix == null) return null;
    final pattern = '$prefix:$propName';

    final el =
        _rdfDescription!.children.whereType<xml.XmlElement>().firstWhere((e) {
      return e.name.qualified == pattern ||
          (e.name.local == propName && e.name.namespaceUri == schemaNS);
    }, orElse: () => xml.XmlElement(xml.XmlName('dummy')));
    if (el.name.local == 'dummy') return null;
    return el.innerText;
  }

  xml.XmlDocument getDocument() => _doc;
}

class XMPMetaFactory {
  static XMPMeta create() {
    return XMPMeta.create();
  }

  static XMPMeta parseFromBuffer(List<int> buffer) {
    final str = utf8.decode(buffer);
    return parseFromString(str);
  }

  static XMPMeta parseFromString(String packet) {
    try {
      // XMP packets are often wrapped in <?xpacket ... ?>
      // xml parser should handle it if it's valid XML
      // Find start and end of actual XML if needed
      int start = packet.indexOf('<x:xmpmeta');
      int end = packet.indexOf('</x:xmpmeta>');
      if (start != -1 && end != -1) {
        packet = packet.substring(start, end + '</x:xmpmeta>'.length);
      }

      final doc = xml.XmlDocument.parse(packet);
      return XMPMeta(doc);
    } catch (e) {
      // Fallback or rethrow
      return XMPMeta.create(); // Return empty if failed?
    }
  }

  static List<int> serializeToBuffer(XMPMeta xmp, [dynamic options]) {
    return utf8.encode(xmp.getDocument().toXmlString());
  }
}
