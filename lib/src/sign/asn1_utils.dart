import 'dart:typed_data';

/// ASN.1 DER encoding utilities.
///
/// This provides a simplified interface for common ASN.1 operations
/// used in PDF digital signatures.
class ASN1Utils {
  ASN1Utils._();

  // ASN.1 Tags
  static const int tagBoolean = 0x01;
  static const int tagInteger = 0x02;
  static const int tagBitString = 0x03;
  static const int tagOctetString = 0x04;
  static const int tagNull = 0x05;
  static const int tagOid = 0x06;
  static const int tagUtf8String = 0x0C;
  static const int tagPrintableString = 0x13;
  static const int tagUtcTime = 0x17;
  static const int tagGeneralizedTime = 0x18;
  static const int tagSequence = 0x30;
  static const int tagSet = 0x31;

  /// Encodes a value with the given tag.
  static Uint8List _encodeTagged(int tag, Uint8List value) {
    final length = value.length;
    final builder = BytesBuilder();
    builder.addByte(tag);

    if (length < 128) {
      builder.addByte(length);
    } else if (length < 256) {
      builder.addByte(0x81);
      builder.addByte(length);
    } else if (length < 65536) {
      builder.addByte(0x82);
      builder.addByte((length >> 8) & 0xFF);
      builder.addByte(length & 0xFF);
    } else {
      builder.addByte(0x83);
      builder.addByte((length >> 16) & 0xFF);
      builder.addByte((length >> 8) & 0xFF);
      builder.addByte(length & 0xFF);
    }

    builder.add(value);
    return builder.toBytes();
  }

  /// Creates an ASN.1 SEQUENCE from a list of encoded elements.
  static Uint8List createSequence(List<Uint8List> elements) {
    final builder = BytesBuilder();
    for (final element in elements) {
      builder.add(element);
    }
    return _encodeTagged(tagSequence, builder.toBytes());
  }

  /// Creates an ASN.1 SET from a list of encoded elements.
  static Uint8List createSet(List<Uint8List> elements) {
    final builder = BytesBuilder();
    for (final element in elements) {
      builder.add(element);
    }
    return _encodeTagged(tagSet, builder.toBytes());
  }

  /// Creates an ASN.1 INTEGER from a BigInt.
  static Uint8List createInteger(BigInt value) {
    var bytes = _bigIntToBytes(value);

    // Ensure minimal encoding - add leading zero if high bit is set
    if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) {
      final newBytes = Uint8List(bytes.length + 1);
      newBytes[0] = 0x00;
      newBytes.setRange(1, bytes.length + 1, bytes);
      bytes = newBytes;
    }

    // Handle zero
    if (bytes.isEmpty) {
      bytes = Uint8List.fromList([0x00]);
    }

    return _encodeTagged(tagInteger, bytes);
  }

  /// Creates an ASN.1 INTEGER from an int.
  static Uint8List createIntegerFromInt(int value) {
    return createInteger(BigInt.from(value));
  }

  /// Creates an ASN.1 OCTET STRING.
  static Uint8List createOctetString(Uint8List data) {
    return _encodeTagged(tagOctetString, data);
  }

  /// Creates an ASN.1 BIT STRING.
  static Uint8List createBitString(Uint8List data, {int unusedBits = 0}) {
    final builder = BytesBuilder();
    builder.addByte(unusedBits);
    builder.add(data);
    return _encodeTagged(tagBitString, builder.toBytes());
  }

  /// Creates an ASN.1 OBJECT IDENTIFIER.
  static Uint8List createOID(String oid) {
    final parts = oid.split('.').map((e) => int.parse(e)).toList();
    if (parts.length < 2) {
      throw ArgumentError('Invalid OID: $oid');
    }

    final builder = BytesBuilder();

    // First two components are encoded as (x * 40) + y
    builder.addByte(parts[0] * 40 + parts[1]);

    // Remaining components use base-128 encoding
    for (int i = 2; i < parts.length; i++) {
      _encodeBase128(builder, parts[i]);
    }

    return _encodeTagged(tagOid, builder.toBytes());
  }

  /// Creates an ASN.1 NULL.
  static Uint8List createNull() {
    return Uint8List.fromList([tagNull, 0x00]);
  }

  /// Creates an ASN.1 BOOLEAN.
  static Uint8List createBoolean(bool value) {
    return _encodeTagged(tagBoolean, Uint8List.fromList([value ? 0xFF : 0x00]));
  }

  /// Creates an ASN.1 UTF8 STRING.
  static Uint8List createUtf8String(String value) {
    return _encodeTagged(tagUtf8String, Uint8List.fromList(value.codeUnits));
  }

  /// Creates an ASN.1 PRINTABLE STRING.
  static Uint8List createPrintableString(String value) {
    return _encodeTagged(
        tagPrintableString, Uint8List.fromList(value.codeUnits));
  }

  /// Creates an ASN.1 UTC TIME.
  static Uint8List createUtcTime(DateTime dateTime) {
    final utc = dateTime.toUtc();
    final formatted = '${_twoDigit(utc.year % 100)}'
        '${_twoDigit(utc.month)}'
        '${_twoDigit(utc.day)}'
        '${_twoDigit(utc.hour)}'
        '${_twoDigit(utc.minute)}'
        '${_twoDigit(utc.second)}Z';
    return _encodeTagged(tagUtcTime, Uint8List.fromList(formatted.codeUnits));
  }

  /// Creates a context-specific tagged object.
  static Uint8List createTagged(int tagNumber, Uint8List content,
      {bool isConstructed = true, bool isExplicit = true}) {
    final tag = (isConstructed ? 0xA0 : 0x80) | (tagNumber & 0x1F);
    if (isExplicit) {
      return _encodeTagged(tag, content);
    } else {
      // Implicit tagging - replace the tag of the content
      final result = BytesBuilder();
      result.addByte(tag);
      result.add(content.sublist(1)); // Skip original tag
      return result.toBytes();
    }
  }

  /// Parses an ASN.1 DER-encoded structure.
  static ASN1ParseResult parse(Uint8List data, [int offset = 0]) {
    if (offset >= data.length) {
      throw FormatException('Unexpected end of data');
    }

    final tag = data[offset];
    offset++;

    // Parse length
    int length;
    if (data[offset] < 128) {
      length = data[offset];
      offset++;
    } else {
      final numLengthBytes = data[offset] & 0x7F;
      offset++;
      length = 0;
      for (int i = 0; i < numLengthBytes; i++) {
        length = (length << 8) | data[offset];
        offset++;
      }
    }

    final content = data.sublist(offset, offset + length);
    return ASN1ParseResult(tag, content, offset + length);
  }

  /// Parses a SEQUENCE and returns the list of elements.
  static List<ASN1ParseResult> parseSequence(Uint8List data) {
    final result = parse(data);
    if ((result.tag & 0x1F) != 0x10) {
      throw FormatException('Expected SEQUENCE');
    }
    return parseElements(result.content);
  }

  /// Parses a series of elements from raw content.
  static List<ASN1ParseResult> parseElements(Uint8List content) {
    final elements = <ASN1ParseResult>[];
    int offset = 0;

    while (offset < content.length) {
      // Parse tag
      if (offset >= content.length) break;
      final tag = content[offset];
      int headerLen = 1;

      // Parse length
      if (offset + 1 >= content.length) break;
      int length;
      int lengthOffset = offset + 1;

      if (content[lengthOffset] < 128) {
        length = content[lengthOffset];
        headerLen = 2;
      } else {
        final numLengthBytes = content[lengthOffset] & 0x7F;
        headerLen = 2 + numLengthBytes;
        length = 0;
        for (int i = 0; i < numLengthBytes; i++) {
          if (lengthOffset + 1 + i >= content.length) {
            throw FormatException('Unexpected end of length bytes');
          }
          length = (length << 8) | content[lengthOffset + 1 + i];
        }
      }

      // Extract content
      final contentStart = offset + headerLen;
      if (contentStart + length > content.length) {
        throw FormatException('Content extends beyond data');
      }

      final elementContent =
          content.sublist(contentStart, contentStart + length);
      elements.add(ASN1ParseResult(tag, elementContent, headerLen + length));

      offset = contentStart + length;
    }

    return elements;
  }

  // Helper methods

  static void _encodeBase128(BytesBuilder builder, int value) {
    if (value == 0) {
      builder.addByte(0);
      return;
    }

    final bytes = <int>[];
    while (value > 0) {
      bytes.insert(0, value & 0x7F);
      value >>= 7;
    }

    for (int i = 0; i < bytes.length - 1; i++) {
      builder.addByte(bytes[i] | 0x80);
    }
    builder.addByte(bytes.last);
  }

  static Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) {
      return Uint8List.fromList([0]);
    }

    final isNegative = value.isNegative;
    value = value.abs();

    final bytes = <int>[];
    while (value > BigInt.zero) {
      bytes.insert(0, (value & BigInt.from(0xFF)).toInt());
      value >>= 8;
    }

    if (isNegative) {
      // Two's complement for negative numbers
      for (int i = 0; i < bytes.length; i++) {
        bytes[i] = (~bytes[i]) & 0xFF;
      }
      // Add one
      int carry = 1;
      for (int i = bytes.length - 1; i >= 0 && carry > 0; i--) {
        int sum = bytes[i] + carry;
        bytes[i] = sum & 0xFF;
        carry = sum >> 8;
      }
    }

    return Uint8List.fromList(bytes);
  }

  static String _twoDigit(int n) => n.toString().padLeft(2, '0');
}

/// Result of parsing an ASN.1 element.
class ASN1ParseResult {
  /// The tag byte.
  final int tag;

  /// The content bytes (without tag and length).
  final Uint8List content;

  /// Total length including tag and length bytes.
  final int totalLength;

  ASN1ParseResult(this.tag, this.content, this.totalLength);

  /// Whether this is a SEQUENCE.
  bool get isSequence => (tag & 0x1F) == 0x10;

  /// Whether this is a SET.
  bool get isSet => (tag & 0x1F) == 0x11;

  /// Whether this is an INTEGER.
  bool get isInteger => tag == ASN1Utils.tagInteger;

  /// Whether this is an OCTET STRING.
  bool get isOctetString => tag == ASN1Utils.tagOctetString;

  /// Whether this is an OID.
  bool get isOid => tag == ASN1Utils.tagOid;

  /// Whether this is context-specific tagged.
  bool get isContextSpecific => (tag & 0xC0) == 0x80;

  /// Gets the tag number for context-specific tags.
  int get tagNumber => tag & 0x1F;
}
