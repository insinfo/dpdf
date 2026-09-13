import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/sign/x500_name.dart';
import 'package:test/test.dart';

/// Builds a DER `Name` with one relative distinguished name per entry.
///
/// Each entry maps an attribute type OID onto a value tag and its content
/// octets, so the tests can vary the string choice and the spacing without
/// depending on a certificate generator.
Uint8List name(List<Map<String, (int, List<int>)>> rdns) {
  final body = <int>[];
  for (final rdn in rdns) {
    final attributes = <List<int>>[];
    for (final entry in rdn.entries) {
      final value = _tlv(entry.value.$1, entry.value.$2);
      final attribute = _tlv(0x30, [..._oid(entry.key), ...value]);
      attributes.add(attribute);
    }
    attributes.sort(_derOrder);
    body.addAll(_tlv(0x31, attributes.expand((a) => a).toList()));
  }
  return Uint8List.fromList(_tlv(0x30, body));
}

int _derOrder(List<int> a, List<int> b) {
  for (var index = 0; index < a.length && index < b.length; index++) {
    if (a[index] != b[index]) return a[index] - b[index];
  }
  return a.length - b.length;
}

List<int> _tlv(int tag, List<int> value) {
  final length = <int>[];
  var n = value.length;
  if (n < 128) {
    length.add(n);
  } else {
    while (n > 0) {
      length.insert(0, n & 0xff);
      n >>= 8;
    }
    length.insert(0, 0x80 | length.length);
  }
  return [tag, ...length, ...value];
}

List<int> _oid(String dotted) {
  final arcs = dotted.split('.').map(int.parse).toList();
  final body = <int>[arcs[0] * 40 + arcs[1]];
  for (final arc in arcs.skip(2)) {
    final encoded = <int>[arc & 0x7f];
    var rest = arc >> 7;
    while (rest > 0) {
      encoded.insert(0, (rest & 0x7f) | 0x80);
      rest >>= 7;
    }
    body.addAll(encoded);
  }
  return _tlv(0x06, body);
}

const String commonName = '2.5.4.3';
const String organization = '2.5.4.10';
const int printableString = 19;
const int utf8String = 12;
const int bmpString = 30;

List<int> ascii(String value) => latin1.encode(value);

List<int> ucs2(String value) {
  final bytes = <int>[];
  for (final unit in value.codeUnits) {
    bytes.add((unit >> 8) & 0xff);
    bytes.add(unit & 0xff);
  }
  return bytes;
}

void main() {
  group('RFC 5280 section 7.1 name matching', () {
    test('identical encodings match', () {
      final a = name([
        {commonName: (printableString, ascii('DPDF Test CA'))}
      ]);
      expect(X500Name.derEquals(a, Uint8List.fromList(a)), isTrue);
    });

    test('the string choice does not change the identity', () {
      final printable = name([
        {commonName: (printableString, ascii('DPDF Test CA'))}
      ]);
      final utf8Encoded = name([
        {commonName: (utf8String, utf8.encode('DPDF Test CA'))}
      ]);
      final bmp = name([
        {commonName: (bmpString, ucs2('DPDF Test CA'))}
      ]);
      expect(X500Name.derEquals(printable, utf8Encoded), isTrue);
      expect(X500Name.derEquals(printable, bmp), isTrue);
      expect(X500Name.derEquals(utf8Encoded, bmp), isTrue);
    });

    test('case and insignificant spaces are folded away', () {
      final a = name([
        {commonName: (printableString, ascii('DPDF   Test  CA'))}
      ]);
      final b = name([
        {commonName: (utf8String, utf8.encode('  dpdf test ca '))}
      ]);
      expect(X500Name.derEquals(a, b), isTrue);
    });

    test('characters that map to nothing are ignored', () {
      final a = name([
        {commonName: (utf8String, utf8.encode('DPDF Test CA'))}
      ]);
      final b = name([
        {commonName: (utf8String, utf8.encode('DPDF\u00ADTest\u200BCA'))}
      ]);
      // The soft hyphen and the zero width space disappear, but the space that
      // separated the words in the first name does not.
      expect(X500Name.derEquals(a, b), isFalse);
      final c = name([
        {commonName: (utf8String, utf8.encode('DPDF\u00AD Test \u200BCA'))}
      ]);
      expect(X500Name.derEquals(a, c), isTrue);
    });

    test('a different value or attribute type does not match', () {
      final a = name([
        {commonName: (printableString, ascii('DPDF Test CA'))}
      ]);
      final b = name([
        {commonName: (printableString, ascii('DPDF Other CA'))}
      ]);
      final c = name([
        {organization: (printableString, ascii('DPDF Test CA'))}
      ]);
      expect(X500Name.derEquals(a, b), isFalse);
      expect(X500Name.derEquals(a, c), isFalse);
    });

    test('the order of the relative distinguished names is significant', () {
      final a = name([
        {organization: (printableString, ascii('DPDF'))},
        {commonName: (printableString, ascii('CA'))},
      ]);
      final b = name([
        {commonName: (printableString, ascii('CA'))},
        {organization: (printableString, ascii('DPDF'))},
      ]);
      expect(X500Name.derEquals(a, b), isFalse);
    });

    test('attributes inside one relative distinguished name are a set', () {
      final a = name([
        {
          commonName: (printableString, ascii('CA')),
          organization: (printableString, ascii('DPDF')),
        }
      ]);
      final b = name([
        {
          organization: (utf8String, utf8.encode('dpdf')),
          commonName: (utf8String, utf8.encode('ca')),
        }
      ]);
      expect(X500Name.derEquals(a, b), isTrue);
    });

    test('a name with a different number of components does not match', () {
      final a = name([
        {commonName: (printableString, ascii('CA'))}
      ]);
      final b = name([
        {commonName: (printableString, ascii('CA'))},
        {organization: (printableString, ascii('DPDF'))},
      ]);
      expect(X500Name.derEquals(a, b), isFalse);
    });

    test('unparsable names only match byte for byte', () {
      final garbage = Uint8List.fromList([0x05, 0x00]);
      expect(X500Name.derEquals(garbage, Uint8List.fromList([0x05, 0x00])),
          isTrue);
      expect(
          X500Name.derEquals(
              garbage,
              name([
                {commonName: (printableString, ascii('CA'))}
              ])),
          isFalse);
      expect(X500Name.tryParse(garbage), isNull);
    });

    test('the canonical form is stable across encodings', () {
      final printable = X500Name.tryParse(name([
        {commonName: (printableString, ascii('DPDF  Test CA'))}
      ]))!;
      final utf8Encoded = X500Name.tryParse(name([
        {commonName: (utf8String, utf8.encode('dpdf test ca'))}
      ]))!;
      expect(printable.canonicalForm(), utf8Encoded.canonicalForm());
      expect(printable.canonicalForm(), '2.5.4.3=dpdf test ca');
    });

    test('non textual values fall back to their content octets', () {
      final a = name([
        {commonName: (0x04, const [1, 2, 3])}
      ]);
      final b = name([
        {commonName: (0x04, const [1, 2, 3])}
      ]);
      final c = name([
        {commonName: (0x04, const [1, 2, 4])}
      ]);
      expect(X500Name.derEquals(a, b), isTrue);
      expect(X500Name.derEquals(a, c), isFalse);
    });
  });

  group('RFC 4518 string preparation', () {
    test('folds case and collapses inner space runs', () {
      expect(X500Attribute.prepareString('  A  B  '), 'a b');
    });

    test('maps tabs and non breaking spaces onto spaces', () {
      expect(X500Attribute.prepareString('a\tb\u00A0c'), 'a b c');
    });

    test('removes zero width characters', () {
      expect(X500Attribute.prepareString('a\u200Bb'), 'ab');
    });
  });
}
