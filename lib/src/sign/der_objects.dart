import 'dart:convert';
import 'dart:typed_data';

/// Definite-length ASN.1 value model used by X.509 and CMS (ITU-T X.690).
class ASN1Object {
  final int tag;
  final Uint8List valueBytes;
  ASN1Object(this.tag, List<int> value)
      : valueBytes = Uint8List.fromList(value);
  factory ASN1Object.fromBytes(Uint8List bytes) =>
      ASN1Parser(bytes).readSingle();
  Uint8List? get encodedBytes => encode();
  Uint8List encode() {
    final length = <int>[];
    var n = valueBytes.length;
    if (n < 128) {
      length.add(n);
    } else {
      while (n > 0) {
        length.insert(0, n & 255);
        n >>= 8;
      }
      length.insert(0, 128 | length.length);
    }
    return Uint8List.fromList([tag, ...length, ...valueBytes]);
  }
}

class ASN1Sequence extends ASN1Object {
  final List<ASN1Object>? elements;
  ASN1Sequence({List<ASN1Object>? elements, int tag = 0x30})
      : elements = elements ?? [],
        super(tag, []);
  void add(ASN1Object object) => elements!.add(object);
  @override
  Uint8List encode() =>
      ASN1Object(tag, elements!.expand((v) => v.encode()).toList()).encode();
}

class ASN1Set extends ASN1Sequence {
  ASN1Set({super.elements}) : super(tag: 0x31);
  @override
  Uint8List encode() {
    final items = elements!.map((e) => e.encode()).toList();
    items.sort((a, b) {
      for (var i = 0; i < a.length && i < b.length; i++) {
        if (a[i] != b[i]) return a[i] - b[i];
      }
      return a.length - b.length;
    });
    return ASN1Object(tag, items.expand((e) => e).toList()).encode();
  }
}

class ASN1Integer extends ASN1Object {
  final BigInt? integer;
  ASN1Integer(BigInt? value, {int tag = 2})
      : integer = value ?? BigInt.zero,
        super(tag, _bytes(value ?? BigInt.zero));
  static List<int> _bytes(BigInt v) {
    var size = 1;
    while (v < -(BigInt.one << (size * 8 - 1)) ||
        v >= (BigInt.one << (size * 8 - 1))) size++;
    final result = List<int>.filled(size, 0);
    for (var i = size - 1; i >= 0; i--) {
      result[i] = (v & BigInt.from(255)).toInt();
      v >>= 8;
    }
    return result;
  }
}

class ASN1Enumerated extends ASN1Integer {
  ASN1Enumerated(BigInt value) : super(value, tag: 10);
}

class ASN1OctetString extends ASN1Object {
  Uint8List get octets => valueBytes;
  ASN1OctetString({required List<int> octets}) : super(4, octets);
}

class ASN1BitString extends ASN1Object {
  final Uint8List stringValues;
  final int unusedBits;
  ASN1BitString({required List<int> stringValues, this.unusedBits = 0})
      : stringValues = Uint8List.fromList(stringValues),
        super(3, [unusedBits, ...stringValues]);
}

class ASN1Null extends ASN1Object {
  ASN1Null() : super(5, []);
}

class ASN1Boolean extends ASN1Object {
  final bool? boolValue;
  ASN1Boolean(bool value)
      : boolValue = value,
        super(1, [value ? 255 : 0]);
}

class ASN1PrintableString extends ASN1Object {
  final String stringValue;
  ASN1PrintableString({required this.stringValue})
      : super(19, ascii.encode(stringValue));
}

class ASN1UtcTime extends ASN1Object {
  final DateTime time;
  ASN1UtcTime(DateTime value)
      : time = value.toUtc(),
        super(value.toUtc().year >= 2050 || value.toUtc().year < 1950 ? 24 : 23,
            _encode(value.toUtc()));
  static List<int> _encode(DateTime d) {
    String p(int n) => n.toString().padLeft(2, '0');
    final year = d.year >= 2050 || d.year < 1950
        ? d.year.toString().padLeft(4, '0')
        : p(d.year % 100);
    return ascii.encode(
        '$year${p(d.month)}${p(d.day)}${p(d.hour)}${p(d.minute)}${p(d.second)}Z');
  }
}

class ASN1ObjectIdentifier extends ASN1Object {
  final String? objectIdentifierAsString;
  ASN1ObjectIdentifier.fromIdentifierString(String oid)
      : objectIdentifierAsString = oid,
        super(6, _encode(oid));
  factory ASN1ObjectIdentifier.fromName(String oid) =>
      ASN1ObjectIdentifier.fromIdentifierString(oid);
  static List<int> _encode(String oid) {
    final parts = oid.split('.').map(BigInt.parse).toList();
    if (parts.length < 2 ||
        parts[0] < BigInt.zero ||
        parts[0] > BigInt.two ||
        parts[1] < BigInt.zero ||
        (parts[0] < BigInt.two && parts[1] >= BigInt.from(40)))
      throw FormatException('Invalid object identifier');
    final result = <int>[];
    for (var value in [
      parts[0] * BigInt.from(40) + parts[1],
      ...parts.skip(2)
    ]) {
      if (value < BigInt.zero) throw FormatException('Negative OID arc');
      final arc = <int>[(value & BigInt.from(127)).toInt()];
      value >>= 7;
      while (value > BigInt.zero) {
        arc.insert(0, 128 | (value & BigInt.from(127)).toInt());
        value >>= 7;
      }
      result.addAll(arc);
    }
    return result;
  }
}

class ASN1Parser {
  final Uint8List bytes;
  int _offset = 0;
  final int _depth;
  ASN1Parser(this.bytes) : _depth = 0;
  ASN1Parser._(this.bytes, this._depth);
  bool get isAtEnd => _offset == bytes.length;
  int get consumedBytes => _offset;
  ASN1Object readSingle() {
    final result = nextObject();
    if (!isAtEnd) throw FormatException('Trailing data after ASN.1 object');
    return result;
  }

  ASN1Object nextObject() {
    if (_depth > 64 || _offset + 2 > bytes.length)
      throw FormatException('Truncated or deeply nested ASN.1');
    final tag = bytes[_offset++];
    if ((tag & 31) == 31) throw FormatException('High ASN.1 tag unsupported');
    var length = bytes[_offset++];
    if (length >= 128) {
      final count = length & 127;
      if (count == 0 || count > 4 || _offset + count > bytes.length)
        throw FormatException('Invalid ASN.1 length');
      if (bytes[_offset] == 0) throw FormatException('Nonminimal ASN.1 length');
      length = 0;
      for (var i = 0; i < count; i++) length = (length << 8) | bytes[_offset++];
      if (length < 128) throw FormatException('Nonminimal ASN.1 length');
    }
    if (_offset + length > bytes.length)
      throw FormatException('Truncated ASN.1 value');
    final value = Uint8List.fromList(bytes.sublist(_offset, _offset + length));
    _offset += length;
    if ((tag & 32) != 0) {
      if ((tag & 0xc0) == 0 && tag != 0x30 && tag != 0x31) {
        throw FormatException(
            'Constructed encoding is not permitted for this DER tag');
      }
      final parser = ASN1Parser._(value, _depth + 1);
      final elements = <ASN1Object>[];
      while (parser._offset < value.length) elements.add(parser.nextObject());
      if (tag == 49) {
        for (var i = 1; i < elements.length; i++) {
          final previous = elements[i - 1].encode(),
              current = elements[i].encode();
          var comparison = previous.length.compareTo(current.length);
          for (var j = 0; j < previous.length && j < current.length; j++) {
            if (previous[j] != current[j]) {
              comparison = previous[j].compareTo(current[j]);
              break;
            }
          }
          if (comparison > 0) throw FormatException('Unsorted DER SET');
        }
      }
      return tag == 49
          ? ASN1Set(elements: elements)
          : ASN1Sequence(elements: elements, tag: tag);
    }
    switch (tag) {
      case 2:
      case 10:
        if (value.isEmpty) throw FormatException('Empty ASN.1 integer');
        if (value.length > 1 &&
            ((value[0] == 0 && value[1] & 128 == 0) ||
                (value[0] == 255 && value[1] & 128 != 0))) {
          throw FormatException('Nonminimal ASN.1 integer');
        }
        var n = BigInt.zero;
        for (final b in value) n = (n << 8) | BigInt.from(b);
        if (value[0] & 128 != 0) n -= BigInt.one << (value.length * 8);
        return tag == 2 ? ASN1Integer(n) : ASN1Enumerated(n);
      case 1:
        if (value.length != 1 || (value[0] != 0 && value[0] != 255))
          throw FormatException('Invalid DER boolean');
        return ASN1Boolean(value[0] != 0);
      case 3:
        if (value.isEmpty || value[0] > 7)
          throw FormatException('Invalid bit string');
        if ((value.length == 1 && value[0] != 0) ||
            (value.length > 1 && value.last & ((1 << value[0]) - 1) != 0)) {
          throw FormatException('Invalid bit-string padding');
        }
        return ASN1BitString(
            stringValues: value.sublist(1), unusedBits: value[0]);
      case 4:
        return ASN1OctetString(octets: value);
      case 5:
        if (value.isNotEmpty) throw FormatException('Invalid NULL');
        return ASN1Null();
      case 6:
        final arcs = <BigInt>[];
        var arc = BigInt.zero;
        var start = true;
        for (final b in value) {
          if (start && b == 128) throw FormatException('Nonminimal OID arc');
          arc = (arc << 7) | BigInt.from(b & 127);
          start = false;
          if (b & 128 == 0) {
            arcs.add(arc);
            arc = BigInt.zero;
            start = true;
          }
        }
        if (arcs.isEmpty || value.last & 128 != 0)
          throw FormatException('Invalid OID');
        final first = arcs.removeAt(0);
        final a = first < BigInt.from(40)
            ? 0
            : first < BigInt.from(80)
                ? 1
                : 2;
        return ASN1ObjectIdentifier.fromIdentifierString(
            [BigInt.from(a), first - BigInt.from(a * 40), ...arcs].join('.'));
      default:
        return ASN1Object(tag, value);
    }
  }
}
