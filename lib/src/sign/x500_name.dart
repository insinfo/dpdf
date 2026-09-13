import 'dart:convert';
import 'dart:typed_data';

import 'der_objects.dart';

/// One AttributeTypeAndValue of an X.501 relative distinguished name.
class X500Attribute {
  /// Dotted decimal OID of the attribute type.
  final String type;

  /// DER tag of the attribute value.
  final int valueTag;

  /// Raw DER content octets of the attribute value.
  final Uint8List valueBytes;

  X500Attribute(this.type, this.valueTag, this.valueBytes);

  /// True when the value is one of the DirectoryString choices, IA5String or
  /// one of the deprecated string types that RFC 4518 prepares as text.
  bool get isTextual => const {
        12, // UTF8String
        18, // NumericString
        19, // PrintableString
        20, // TeletexString / T61String
        22, // IA5String
        26, // VisibleString / ISO646String
        27, // GeneralString
        28, // UniversalString
        30, // BMPString
      }.contains(valueTag);

  /// The value decoded into text, or null when the type is not textual.
  String? get text {
    if (!isTextual) return null;
    switch (valueTag) {
      case 30: // BMPString: UCS-2, big endian.
        return _decodeUcs(valueBytes, 2);
      case 28: // UniversalString: UCS-4, big endian.
        return _decodeUcs(valueBytes, 4);
      case 12:
        return utf8.decode(valueBytes, allowMalformed: true);
      default:
        // The remaining choices are ASCII compatible in practice; Teletex is
        // treated as Latin-1, which is what every issuer emits.
        return latin1.decode(valueBytes, allowInvalid: true);
    }
  }

  /// The value after the RFC 4518 string preparation used by caseIgnoreMatch.
  ///
  /// Non textual values have no canonical text form and are compared through
  /// their DER content octets instead, which this getter returns as a
  /// hexadecimal escape so that it can never collide with prepared text.
  String get canonicalValue {
    final value = text;
    if (value == null) {
      final buffer = StringBuffer('#');
      for (final byte in valueBytes) {
        buffer.write(byte.toRadixString(16).padLeft(2, '0'));
      }
      return buffer.toString();
    }
    return prepareString(value);
  }

  /// RFC 4518 string preparation, restricted to the steps that matter for
  /// comparing distinguished names produced by real certificate authorities.
  ///
  /// Transcoding already happened while decoding; this applies the Map,
  /// Normalize (as far as case folding goes), Prohibit-free and Insignificant
  /// Character Handling steps: characters that map to nothing are removed,
  /// every other mapped character becomes a space, the result is case folded
  /// and inner space runs collapse to a single space with leading and trailing
  /// space removed.
  static String prepareString(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (_mapsToNothing(rune)) continue;
      if (_mapsToSpace(rune)) {
        buffer.write(' ');
        continue;
      }
      buffer.writeCharCode(rune);
    }
    final folded = buffer.toString().toLowerCase();
    return folded.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _mapsToNothing(int rune) {
    // SOFT HYPHEN, zero width characters, combining grapheme joiner, variation
    // selectors, BOM and the RFC 3454 table B.1 control set.
    if (rune == 0x00AD || rune == 0x034F || rune == 0x1806) return true;
    if (rune >= 0x180B && rune <= 0x180D) return true;
    if (rune >= 0x200B && rune <= 0x200F) return true;
    if (rune >= 0x202A && rune <= 0x202E) return true;
    if (rune >= 0x2060 && rune <= 0x2064) return true;
    if (rune >= 0x206A && rune <= 0x206F) return true;
    if (rune == 0xFEFF) return true;
    if (rune >= 0xFE00 && rune <= 0xFE0F) return true;
    if (rune == 0x00A0) return false;
    return false;
  }

  static bool _mapsToSpace(int rune) {
    if (rune == 0x0009 ||
        rune == 0x000A ||
        rune == 0x000B ||
        rune == 0x000C ||
        rune == 0x000D ||
        rune == 0x0085) {
      return true;
    }
    if (rune == 0x00A0 || rune == 0x1680) return true;
    if (rune >= 0x2000 && rune <= 0x200A) return true;
    if (rune == 0x2028 || rune == 0x2029) return true;
    if (rune == 0x202F || rune == 0x205F || rune == 0x3000) return true;
    return false;
  }

  static String _decodeUcs(Uint8List bytes, int width) {
    final runes = <int>[];
    for (var index = 0; index + width <= bytes.length; index += width) {
      var rune = 0;
      for (var offset = 0; offset < width; offset++) {
        rune = (rune << 8) | bytes[index + offset];
      }
      runes.add(rune);
    }
    return String.fromCharCodes(runes);
  }
}

/// An X.501 distinguished name parsed out of its DER encoding.
///
/// Comparison follows RFC 5280 section 7.1: two names match when they have the
/// same number of relative distinguished names in the same order, each pair of
/// relative distinguished names holds the same set of attributes, and matching
/// attributes share the attribute type and compare equal after the RFC 4518
/// preparation of their values.
class X500Name {
  /// The relative distinguished names, outermost first.
  final List<List<X500Attribute>> rdns;

  X500Name(this.rdns);

  /// Parses a `Name` from its DER encoding, returning null when the bytes are
  /// not a well formed RDNSequence.
  static X500Name? tryParse(Uint8List der) {
    try {
      final root = ASN1Parser(der).nextObject();
      if (root is! ASN1Sequence || root is ASN1Set) return null;
      final rdns = <List<X500Attribute>>[];
      for (final rdn in root.elements ?? const <ASN1Object>[]) {
        if (rdn is! ASN1Set) return null;
        final attributes = <X500Attribute>[];
        for (final ava in rdn.elements ?? const <ASN1Object>[]) {
          if (ava is! ASN1Sequence || ava.elements == null) return null;
          if (ava.elements!.length < 2) return null;
          final type = ava.elements![0];
          if (type is! ASN1ObjectIdentifier ||
              type.objectIdentifierAsString == null) {
            return null;
          }
          final value = ava.elements![1];
          attributes.add(X500Attribute(
              type.objectIdentifierAsString!, value.tag, value.valueBytes));
        }
        if (attributes.isEmpty) return null;
        rdns.add(attributes);
      }
      return X500Name(rdns);
    } catch (_) {
      return null;
    }
  }

  /// The canonical form used for comparison and as a map key.
  String canonicalForm() {
    final parts = <String>[];
    for (final rdn in rdns) {
      final attributes = rdn
          .map((attribute) => '${attribute.type}=${attribute.canonicalValue}')
          .toList()
        ..sort();
      parts.add(attributes.join('+'));
    }
    return parts.join(',');
  }

  /// True when this name matches [other] under RFC 5280 section 7.1.
  bool matches(X500Name other) {
    if (rdns.length != other.rdns.length) return false;
    for (var index = 0; index < rdns.length; index++) {
      final mine = rdns[index], theirs = other.rdns[index];
      if (mine.length != theirs.length) return false;
      final remaining = List<X500Attribute>.from(theirs);
      for (final attribute in mine) {
        final match = remaining.indexWhere((candidate) =>
            candidate.type == attribute.type &&
            candidate.canonicalValue == attribute.canonicalValue);
        if (match < 0) return false;
        remaining.removeAt(match);
      }
    }
    return true;
  }

  /// Compares two DER encoded names.
  ///
  /// Byte equality short circuits the comparison; otherwise both names are
  /// parsed and compared under RFC 5280 section 7.1. Names that cannot be
  /// parsed only match when their encodings are identical.
  static bool derEquals(Uint8List a, Uint8List b) {
    if (a.length == b.length) {
      var identical = true;
      for (var index = 0; index < a.length; index++) {
        if (a[index] != b[index]) {
          identical = false;
          break;
        }
      }
      if (identical) return true;
    }
    final left = tryParse(a), right = tryParse(b);
    if (left == null || right == null) return false;
    return left.matches(right);
  }
}
