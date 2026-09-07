import 'dart:convert';

import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import 'pdf_conformance.dart';

/// The profile identifiers a document declares in its XMP packet.
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

  const XmpIdentification({
    this.pdfALevel,
    this.pdfAPart,
    this.pdfAConformance,
    this.pdfUALevel,
    this.title,
  });

  static const XmpIdentification none = XmpIdentification();

  /// Reads the identifiers from the catalog's `/Metadata` stream.
  ///
  /// The packet is read as text rather than through an RDF model: the four
  /// values below are the only ones a conformance check needs, and they appear
  /// either as an attribute or as an element, in packets written by any tool.
  static Future<XmpIdentification> read(CraftPdfDictionary catalog) async {
    final stream = await catalog.streamEntry(CraftPdfName.metadata);
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
      title: _title(packet),
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

  static String? _title(String packet) {
    final block =
        RegExp(r'<dc:title[^>]*>([\s\S]*?)</dc:title>').firstMatch(packet);
    if (block == null) return null;
    final alternative =
        RegExp(r'<rdf:li[^>]*>([\s\S]*?)</rdf:li>').firstMatch(block.group(1)!);
    final text = (alternative?.group(1) ?? block.group(1))?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
