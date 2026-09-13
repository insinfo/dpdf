import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/platform/compression.dart';
import 'package:test/test.dart';

Uint8List _bytes(List<Object> parts) {
  final builder = BytesBuilder(copy: false);
  for (final part in parts) {
    if (part is String) {
      builder.add(latin1.encode(part));
    } else {
      builder.add(Uint8List.fromList((part as List).cast<int>()));
    }
  }
  return builder.takeBytes();
}

String _extract(Uint8List content) => PdfTextExtraction.fromContent(content,
    decoder: (_, codes) => latin1.decode(codes));

/// Eighteen bytes of "image data" that a naive scanner would run straight into:
/// the first four spell a whitespace-delimited `EI`, and the rest spell a text
/// object. A reader that stops at that `EI` emits LEAK; a reader that honours
/// the declared sample count never looks at these bytes at all.
const _trap = ' EI BT(LEAK)Tj ET ';

void main() {
  group('unfiltered inline images', () {
    test('length from /W /H /BPC /CS beats an EI inside the data', () {
      final content = _bytes([
        'BT /F1 12 Tf (before) Tj ET\n',
        'BI /W 6 /H 3 /BPC 8 /CS /G ID ',
        _trap,
        ' EI\n',
        'BT /F1 12 Tf (after) Tj ET',
      ]);
      expect(_trap.length, 18);
      expect(_extract(content), 'beforeafter');
      expect(_extract(content), isNot(contains('LEAK')));
    });

    test('component count follows the colour space abbreviation', () {
      // 2 x 2 DeviceRGB at 8 bits is 12 bytes; six of them spell " EI BT(".
      final data = ' EI BT(LEAK)'.substring(0, 12);
      final content = _bytes([
        'BI /W 2 /H 2 /BPC 8 /CS /RGB ID ',
        data,
        ' EI (tail) Tj',
      ]);
      expect(() => _extract(content), throwsFormatException,
          reason: 'Tj outside BT is still an error, but only after EI.');
      expect(
          _extract(_bytes([
            'BT /F1 12 Tf (a) Tj ET BI /W 2 /H 2 /BPC 8 /CS /RGB ID ',
            data,
            ' EI BT (b) Tj ET',
          ])),
          'ab');
    });

    test('image masks are one bit per sample', () {
      // /IM true means one bit per sample and no colour space: 8 wide by 2
      // high is two bytes, and here both of them are the letters E and I.
      final content = _bytes([
        'BT /F1 12 Tf (a) Tj ET BI /IM true /W 8 /H 2 /D [1 0] ID ',
        [0x45, 0x49],
        ' EI BT (b) Tj ET',
      ]);
      expect(_extract(content), 'ab');
    });

    test('spelled-out keys are accepted alongside the abbreviations', () {
      final content = _bytes([
        'BT /F1 12 Tf (a) Tj ET '
            'BI /Width 4 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray ID ',
        'EI  ' /* four sample bytes that start with EI */,
        ' EI BT (b) Tj ET',
      ]);
      expect(_extract(content), 'ab');
    });

    test('a sample count that disagrees with EI is refused', () {
      final content = _bytes([
        'BI /W 6 /H 3 /BPC 8 /CS /G ID ',
        'too short',
        ' EI',
      ]);
      expect(() => _extract(content), throwsFormatException);
    });

    test('an unbounded inline image is refused, not guessed at', () {
      // A named resource colour space gives no component count, so the data
      // has no computable length and no filter to validate a search against.
      expect(
          () => _extract(_bytes(['BI /W 2 /H 2 /BPC 8 /CS /Cs1 ID abcd EI'])),
          throwsUnsupportedError);
      expect(() => _extract(_bytes(['BI /W 1 /H 1 ID /BPC 8 x EI'])),
          throwsUnsupportedError,
          reason: 'Entries after ID are image data, not dictionary keys.');
    });
  });

  group('filtered inline images', () {
    test('a candidate EI that does not decode is rejected', () {
      // RunLengthDecode: one literal run of 18 bytes, then the 128 end marker.
      // The run's own bytes open with a whitespace-delimited EI, so the first
      // candidate is at index 2; it only survives if nothing validates it.
      final encoded = <int>[17, ...latin1.encode(_trap), 128];
      expect(encoded.length, 20);
      final content = _bytes([
        'BT /F1 12 Tf (before) Tj ET BI /W 6 /H 3 /BPC 8 /CS /G /F /RL ID ',
        encoded,
        ' EI BT /F1 12 Tf (after) Tj ET',
      ]);
      expect(_extract(content), 'beforeafter');
    });

    test('flate data is validated against the declared sample count', () {
      final samples = Uint8List.fromList(List.generate(18, (i) => i * 7 & 255));
      final encoded = zlib.encode(samples);
      final content = _bytes([
        'BT /F1 12 Tf (a) Tj ET BI /W 6 /H 3 /BPC 8 /CS /G /F /Fl ID ',
        encoded,
        ' EI BT (b) Tj ET',
      ]);
      expect(_extract(content), 'ab');
    });

    test('ASCII armoured data may follow ID after any whitespace', () {
      final content = _bytes([
        'BT /F1 12 Tf (a) Tj ET BI /W 4 /H 1 /BPC 8 /CS /G /F /AHx ID\n'
            '  41424344>\nEI BT (b) Tj ET',
      ]);
      expect(_extract(content), 'ab');
    });

    test('flate data of the wrong sample count is not accepted', () {
      // Ten decoded bytes where the entries promise eighteen: the payload
      // decodes cleanly, so only the length check can catch it, and with no
      // other candidate EI the image has no end.
      final encoded = zlib.encode(Uint8List.fromList(List.filled(10, 9)));
      final content = _bytes([
        'BI /W 6 /H 3 /BPC 8 /CS /G /F /Fl ID ',
        encoded,
        ' EI',
      ]);
      expect(() => _extract(content), throwsFormatException);
    });

    test('a filter array validates against the outermost filter', () {
      final samples = Uint8List.fromList(List.filled(6, 0x20));
      final hex = samples
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      final content = _bytes([
        'BT /F1 12 Tf (a) Tj ET BI /W 2 /H 1 /BPC 8 /CS /RGB /F [/AHx /Fl] ID ',
        '$hex>',
        ' EI BT (b) Tj ET',
      ]);
      expect(_extract(content), 'ab');
    });
  });

  group('malformed inline images', () {
    test('an inline image inside a text object is refused', () {
      expect(
          () => _extract(
              _bytes(['BT /F1 12 Tf BI /W 1 /H 1 /BPC 8 /CS /G ID x EI ET'])),
          throwsFormatException);
    });

    test('nesting, missing ID and missing EI are refused', () {
      for (final content in [
        'BI /W 1 /H 1 /BPC 8 /CS /G BI ID x EI EI',
        'BI /W 1 /H 1 /BPC 8 /CS /G',
        'BI /W 1 /H 1 /BPC 8 /CS /G /F /Fl ID abcdef',
        'BI /W 1 /W 2 /H 1 /BPC 8 /CS /G ID x EI',
        'BI 4 /H 1 /BPC 8 /CS /G ID x EI',
      ]) {
        expect(() => _extract(_bytes([content])), throwsFormatException,
            reason: content);
      }
    });
  });

  group('graphics envelope', () {
    test('image bytes are not counted as q or Q operators', () {
      // Four sample bytes spelling "q q " would unbalance a scanner that read
      // the payload as operators; the envelope must add exactly one Q.
      final content = _bytes([
        'q BI /W 4 /H 1 /BPC 8 /CS /G ID ',
        'q q ',
        ' EI',
      ]);
      final wrapped = latin1.decode(PdfGraphicsEnvelope.wrap(content));
      expect(wrapped.startsWith('q\n'), isTrue);
      expect(wrapped.trimRight().endsWith('Q'), isTrue);
      expect('Q\n'.allMatches(wrapped).length, 2);
    });
  });
}
