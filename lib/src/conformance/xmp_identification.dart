import 'dart:convert';

import '../commons/xml/xml.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import 'pdf_conformance.dart';

/// The profile identifiers and the descriptive metadata a document declares in
/// its XMP packet.
class XmpIdentification {
  /// The PDF/A profile named by `pdfaid:part` and `pdfaid:conformance`, when
  /// the pair names a profile this package knows.
  final PdfAConformanceLevel? pdfALevel;

  /// The raw `pdfaid:part` value, even when the pair is unrecognised.
  final String? pdfAPart;

  /// The raw `pdfaid:conformance` value.
  final String? pdfAConformance;

  /// The PDF/UA profile named by `pdfuaid:part`.
  final PdfUAConformanceLevel? pdfUALevel;

  /// The `dc:title` value, which PDF/UA requires.
  final String? title;

  /// The first `dc:creator` entry, which PDF/A expects to agree with the
  /// document information dictionary's `/Author`.
  final String? creator;

  /// The first `dc:description` entry, matching `/Subject`.
  final String? description;

  /// `pdf:Keywords`, matching `/Keywords`.
  final String? keywords;

  /// `pdf:Producer`, matching `/Producer`.
  final String? producer;

  /// `xmp:CreatorTool`, matching `/Creator`.
  final String? creatorTool;

  /// `xmp:CreateDate`, matching `/CreationDate`.
  final String? createDate;

  /// `xmp:ModifyDate`, matching `/ModDate`.
  final String? modifyDate;

  /// True when a packet was found at all.
  final bool present;

  /// Namespace URIs declared through a PDF/A extension schema, i.e. the
  /// `pdfaSchema:namespaceURI` values inside `pdfaExtension:schemas`.
  final Set<String> extensionNamespaces;

  /// Namespace URIs the packet actually carries properties in.
  final Set<String> propertyNamespaces;

  const XmpIdentification({
    this.pdfALevel,
    this.pdfAPart,
    this.pdfAConformance,
    this.pdfUALevel,
    this.title,
    this.creator,
    this.description,
    this.keywords,
    this.producer,
    this.creatorTool,
    this.createDate,
    this.modifyDate,
    this.present = false,
    this.extensionNamespaces = const {},
    this.propertyNamespaces = const {},
  });

  static const XmpIdentification none = XmpIdentification();

  /// Namespaces whose properties a PDF/A file may use without declaring an
  /// extension schema.
  ///
  /// ISO 19005-1 6.7.9 lists the predefined schemas; ISO 19005-2 and -3 add
  /// the EXIF and TIFF ones. A property in any other namespace is only legible
  /// to a later reader if the packet itself describes the schema.
  static const Set<String> predefinedNamespaces = {
    'http://purl.org/dc/elements/1.1/', // dc
    'http://ns.adobe.com/xap/1.0/', // xmp
    'http://ns.adobe.com/xap/1.0/rights/', // xmpRights
    'http://ns.adobe.com/xap/1.0/mm/', // xmpMM
    'http://ns.adobe.com/xap/1.0/bj/', // xmpBJ
    'http://ns.adobe.com/xap/1.0/t/pg/', // xmpTPg
    'http://ns.adobe.com/pdf/1.3/', // pdf
    'http://www.aiim.org/pdfa/ns/id/', // pdfaid
    'http://www.aiim.org/pdfua/ns/id/', // pdfuaid
    'http://www.aiim.org/pdfa/ns/extension/', // pdfaExtension
    'http://www.aiim.org/pdfa/ns/schema#',
    'http://www.aiim.org/pdfa/ns/property#',
    'http://www.aiim.org/pdfa/ns/type#',
    'http://www.aiim.org/pdfa/ns/field#',
    'http://ns.adobe.com/exif/1.0/', // exif
    'http://ns.adobe.com/tiff/1.0/', // tiff
    'http://www.w3.org/1999/02/22-rdf-syntax-ns#', // rdf
    'adobe:ns:meta/', // x
    'http://ns.adobe.com/xmp/note/',
  };

  /// Reads the identifiers from the catalog's `/Metadata` stream.
  static Future<XmpIdentification> read(PdfDictionary catalog) async {
    final stream = await catalog.streamEntry(PdfName.metadata);
    if (stream == null) return none;

    String packet;
    try {
      final bytes = await stream.getBytes();
      if (bytes == null) return none;
      packet = utf8.decode(bytes, allowMalformed: true);
    } on Object {
      return none;
    }
    return parsePacket(packet);
  }

  /// Parses an XMP packet that has already been decoded to text.
  ///
  /// The values are pulled out with a text scan rather than an RDF model: a
  /// packet is RDF/XML, and the same property can be written as an attribute,
  /// as an element, or wrapped in an `rdf:Alt`. Reading all three shapes is
  /// what a validator has to do; building a model of them is not.
  static XmpIdentification parsePacket(String packet) {
    final part = _value(packet, 'pdfaid', 'part');
    final conformance = _value(packet, 'pdfaid', 'conformance');
    final uaPart = _value(packet, 'pdfuaid', 'part');

    return XmpIdentification(
      pdfALevel: part == null
          ? null
          : PdfAConformanceLevel.fromIdentifier(part, conformance),
      pdfAPart: part,
      pdfAConformance: conformance,
      pdfUALevel: uaPart == null
          ? null
          : PdfUAConformanceLevel.values
              .where((level) => level.part == uaPart.trim())
              .firstOrNull,
      title: _text(packet, 'dc', 'title'),
      creator: _text(packet, 'dc', 'creator'),
      description: _text(packet, 'dc', 'description'),
      keywords: _text(packet, 'pdf', 'Keywords'),
      producer: _text(packet, 'pdf', 'Producer'),
      creatorTool: _text(packet, 'xmp', 'CreatorTool') ??
          _text(packet, 'xap', 'CreatorTool'),
      createDate: _text(packet, 'xmp', 'CreateDate') ??
          _text(packet, 'xap', 'CreateDate'),
      modifyDate: _text(packet, 'xmp', 'ModifyDate') ??
          _text(packet, 'xap', 'ModifyDate'),
      present: true,
      extensionNamespaces: _extensionNamespaces(packet),
      propertyNamespaces: _propertyNamespaces(packet),
    );
  }

  /// Reads `<prefix>:<name>` written either as an attribute
  /// (`pdfaid:part="2"`) or as an element (`<pdfaid:part>2</pdfaid:part>`).
  static String? _value(String packet, String prefix, String name) {
    final attribute =
        RegExp('$prefix:$name\\s*=\\s*["\']([^"\']*)["\']').firstMatch(packet);
    if (attribute != null) return attribute.group(1)?.trim();

    final element = RegExp('<$prefix:$name[^>]*>([^<]*)</$prefix:$name>')
        .firstMatch(packet);
    return element?.group(1)?.trim();
  }

  /// Reads a property that may be a plain value, an `rdf:Alt` of language
  /// alternatives, or an `rdf:Seq`/`rdf:Bag` of entries, returning the first
  /// entry in the latter cases.
  static String? _text(String packet, String prefix, String name) {
    final block = RegExp('<$prefix:$name[^>]*>([\\s\\S]*?)</$prefix:$name>')
        .firstMatch(packet);
    if (block == null) {
      final attribute = _value(packet, prefix, name);
      return attribute == null || attribute.isEmpty ? null : attribute;
    }
    final inner = block.group(1)!;
    final item = RegExp(r'<rdf:li[^>]*>([\s\S]*?)</rdf:li>').firstMatch(inner);
    final text = (item?.group(1) ?? inner).trim();
    return text.isEmpty || text.contains('<') ? null : text;
  }

  static Set<String> _extensionNamespaces(String packet) {
    final found = <String>{};
    for (final match in RegExp(
            r'<pdfaSchema:namespaceURI[^>]*>([\s\S]*?)</pdfaSchema:namespaceURI>')
        .allMatches(packet)) {
      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) found.add(value);
    }
    final attributeForm =
        RegExp('pdfaSchema:namespaceURI\\s*=\\s*["\']([^"\']*)["\']');
    for (final match in attributeForm.allMatches(packet)) {
      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) found.add(value);
    }
    return found;
  }

  /// The namespaces of the properties the packet carries.
  ///
  /// Parsing the packet as XML is what makes this answerable: a prefix means
  /// nothing until the `xmlns` declaration in scope is resolved, and only the
  /// resulting URI can be compared with what an extension schema declares.
  /// A packet that does not parse yields no namespaces, so an unparsable
  /// packet never produces a false accusation here.
  static Set<String> _propertyNamespaces(String packet) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(_trimPacketWrapper(packet));
    } on Object {
      return const {};
    }

    final bindings = <String, String>{};
    for (final element in _allElements(document.children)) {
      for (final entry in element.attributes.entries) {
        if (entry.key.startsWith('xmlns:')) {
          bindings[entry.key.substring(6)] = entry.value;
        }
      }
    }

    final namespaces = <String>{};
    for (final description in _allElements(document.children)) {
      if (description.name.local != 'Description') continue;
      for (final key in description.attributes.keys) {
        if (key.startsWith('xmlns') || key == 'rdf:about') continue;
        final prefix = _prefixOf(key);
        final uri = prefix == null ? null : bindings[prefix];
        if (uri != null) namespaces.add(uri);
      }
      for (final child in description.children.whereType<XmlElement>()) {
        final prefix = _prefixOf(child.name.qualified);
        final uri = child.name.namespaceUri ??
            (prefix == null ? null : bindings[prefix]);
        if (uri != null) namespaces.add(uri);
      }
    }
    return namespaces;
  }

  static Iterable<XmlElement> _allElements(List<XmlNode> nodes) sync* {
    for (final node in nodes.whereType<XmlElement>()) {
      yield node;
      yield* _allElements(node.children);
    }
  }

  /// Strips the `<?xpacket?>` wrapper, which is a processing instruction the
  /// XML parser has no reason to accept outside a document.
  static String _trimPacketWrapper(String packet) {
    var text = packet.trim();
    text = text.replaceAll(RegExp(r'<\?xpacket[^?]*\?>'), '');
    return text.trim();
  }

  static String? _prefixOf(String qualified) {
    final index = qualified.indexOf(':');
    return index <= 0 ? null : qualified.substring(0, index);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
