import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/webcapture/web_capture_names.dart';
import 'package:test/test.dart';

Uint8List ascii(String value) => Uint8List.fromList(latin1.encode(value));

String hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('URL strings, ISO 32000-1 14.10.3.2', () {
    test('a relative URL is made absolute against the base', () {
      expect(
          WebCaptureNames.canonicalUrl('faddle/foo.html',
              base: 'http://www.adobe.com/fiddle/initial.html'),
          'http://www.adobe.com/fiddle/faddle/foo.html');
    });

    test('the URL is truncated before the first number sign', () {
      expect(WebCaptureNames.canonicalUrl('http://example.com/a.html#anchor'),
          'http://example.com/a.html');
      expect(WebCaptureNames.canonicalUrl('http://example.com/a#b#c'),
          'http://example.com/a');
    });

    test('the scheme and the host are lowercased', () {
      expect(WebCaptureNames.canonicalUrl('HTTP://WWW.Example.COM/Path/A.html'),
          'http://www.example.com/Path/A.html');
    });

    test('the path keeps its case', () {
      expect(WebCaptureNames.canonicalUrl('http://example.com/MixedCase'),
          'http://example.com/MixedCase');
    });

    test('a file URL on localhost loses the host', () {
      expect(WebCaptureNames.canonicalUrl('file://localhost/c/docs/a.html'),
          'file:///c/docs/a.html');
      expect(WebCaptureNames.canonicalUrl('file://server/c/docs/a.html'),
          'file://server/c/docs/a.html');
    });

    test('a default port is removed and a non default port is kept', () {
      expect(WebCaptureNames.canonicalUrl('http://example.com:80/a'),
          'http://example.com/a');
      expect(WebCaptureNames.canonicalUrl('ftp://example.com:21/a'),
          'ftp://example.com/a');
      expect(WebCaptureNames.canonicalUrl('http://example.com:8080/a'),
          'http://example.com:8080/a');
      expect(WebCaptureNames.canonicalUrl('ftp://example.com:2121/a'),
          'ftp://example.com:2121/a');
    });

    test('dot and double dot path segments are removed', () {
      expect(WebCaptureNames.canonicalUrl('http://example.com/a/./b/../c.html'),
          'http://example.com/a/c.html');
    });

    test('a query string is preserved', () {
      expect(WebCaptureNames.canonicalUrl('HTTP://Example.com/s?q=Foo&r=1#x'),
          'http://example.com/s?q=Foo&r=1');
    });

    test('canonicalisation is idempotent', () {
      const messy = 'HTTP://WWW.Example.COM:80/a/./b/../c.html#frag';
      final once = WebCaptureNames.canonicalUrl(messy);
      expect(WebCaptureNames.canonicalUrl(once), once);
    });
  });

  group('Digital identifiers, ISO 32000-1 14.10.3.3', () {
    test('an image set identifier is the MD5 of the source data', () {
      // RFC 1321 test vector: MD5("abc").
      expect(hex(WebCaptureNames.imageSetIdentifier(ascii('abc'))),
          '900150983cd24fb0d6963f7d28e17f72');
    });

    test(
        'a page set identifier with no auxiliary data is the MD5 of the '
        'source', () {
      expect(hex(WebCaptureNames.pageSetIdentifier(ascii('abc'))),
          hex(WebCaptureNames.imageSetIdentifier(ascii('abc'))));
    });

    test('auxiliary identifiers change the page set identifier', () {
      final plain = WebCaptureNames.pageSetIdentifier(ascii('<html>'));
      final withImage = WebCaptureNames.pageSetIdentifier(
          ascii('<html>'), [WebCaptureNames.imageSetIdentifier(ascii('gif'))]);
      expect(hex(withImage), isNot(hex(plain)));
    });

    test('an auxiliary identifier referenced twice is passed only once', () {
      final image = WebCaptureNames.imageSetIdentifier(ascii('gif'));
      final once = WebCaptureNames.pageSetIdentifier(ascii('<html>'), [image]);
      final twice =
          WebCaptureNames.pageSetIdentifier(ascii('<html>'), [image, image]);
      expect(hex(twice), hex(once));
    });

    test('the order of first reference matters', () {
      final a = WebCaptureNames.imageSetIdentifier(ascii('a'));
      final b = WebCaptureNames.imageSetIdentifier(ascii('b'));
      expect(hex(WebCaptureNames.pageSetIdentifier(ascii('h'), [a, b])),
          isNot(hex(WebCaptureNames.pageSetIdentifier(ascii('h'), [b, a]))));
    });

    test('a text identifier is the MD5 of the text alone', () {
      expect(hex(WebCaptureNames.textIdentifier(ascii('abc'))),
          '900150983cd24fb0d6963f7d28e17f72');
    });
  });

  group('Unique name generation, ISO 32000-1 14.10.3.4', () {
    test('the three special characters of Table 351 are escaped', () {
      final escaped = WebCaptureNames.escapeIdentifier(
          Uint8List.fromList([0x00, 0x2e, 0x5c, 0x41]));
      expect(escaped, [0x5c, 0x30, 0x5c, 0x70, 0x5c, 0x5c, 0x41]);
    });

    test('an identifier without special characters is left alone', () {
      final source = Uint8List.fromList([0x01, 0x7f, 0xff]);
      expect(WebCaptureNames.escapeIdentifier(source), source);
    });

    test('a destination name carries the escaped identifier', () {
      final name = WebCaptureNames.uniqueDestinationName(
          'link', Uint8List.fromList([0x2e, 0x41]));
      expect(name, 'link\\pA');
    });

    test('a field name encodes each byte as two letters from A', () {
      final encoded = WebCaptureNames.encodeForFieldName(
          Uint8List.fromList([0x00, 0x1f, 0xff]));
      expect(encoded, [65, 65, 66, 80, 80, 80]);
    });

    test(
        'a field name never contains a period, so the field separator is '
        'safe', () {
      final identifier =
          Uint8List.fromList(List<int>.generate(16, (i) => i * 17));
      final name = WebCaptureNames.uniqueFieldName('parent.child', identifier);
      expect(name.startsWith('parent.child'), isTrue);
      expect(name.substring('parent.child'.length), isNot(contains('.')));
      expect(name.substring('parent.child'.length), isNot(contains('\\')));
      expect(
          name
              .substring('parent.child'.length)
              .codeUnits
              .every((c) => c >= 65 && c <= 80),
          isTrue);
    });

    test('the field encoding doubles the length of the escaped identifier', () {
      final identifier = Uint8List.fromList([0x2e, 0x2e]);
      final escaped = WebCaptureNames.escapeIdentifier(identifier);
      final name = WebCaptureNames.uniqueFieldName('f', identifier);
      expect(name.length, 1 + escaped.length * 2);
    });
  });
}
