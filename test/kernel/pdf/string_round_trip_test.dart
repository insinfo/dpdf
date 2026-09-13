import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

String _chars(List<int> codes) => String.fromCharCodes(codes);

/// Writes [values] as `/T` entries of one dictionary, reopens the document and
/// returns what came back.
Future<Map<String, List<int>>> _roundTrip(
    Map<String, String> values, {bool hex = false}) async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();

  final probe = PdfDictionary();
  values.forEach((key, value) {
    final string = PdfString(value);
    if (hex) string.setHexWriting(true);
    probe.put(PdfName(key), string);
  });
  page.pdfRepresentation().put(PdfName('Probe'), probe);
  await document.close();

  final reopened = await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
  final read = await (await reopened.pageAt(1))!
      .pdfRepresentation()
      .dictionaryEntry(PdfName('Probe'));

  final result = <String, List<int>>{};
  for (final key in values.keys) {
    final string = await read!.stringEntry(PdfName(key));
    result[key] = string!.getValue().codeUnits;
  }
  return result;
}

void main() {
  group('a string survives being written and read back', () {
    // ISO 32000-1:2008, 7.3.4.2: "An end-of-line marker appearing within a
    // literal string without a preceding REVERSE SOLIDUS shall be treated as a
    // byte value of (0Ah), irrespective of whether the end-of-line marker was
    // a CARRIAGE RETURN (0Dh), a LINE FEED (0Ah), or both."
    //
    // The writer escaped only '(', ')' and '\', so a CARRIAGE RETURN went out
    // raw and came back as a LINE FEED, and a CRLF pair came back as a single
    // byte. Silent data loss, in every string the caller did not mark as hex.

    test('a carriage return is still a carriage return', () async {
      final back = await _roundTrip({'v': _chars([97, 13, 98])});

      expect(back['v'], orderedEquals([97, 13, 98]));
    });

    test('CRLF stays two bytes', () async {
      // The pair is what matters most in practice: 14.10.5.3 requires HTTP
      // headers terminated by CRLF, and a mail or network payload carried in a
      // string has the same need.
      final back = await _roundTrip({'v': _chars([97, 13, 10, 98])});

      expect(back['v'], orderedEquals([97, 13, 10, 98]));
    });

    test('every other control byte already survived, and still does', () async {
      final cases = <String, List<int>>{
        'lf': [97, 10, 98],
        'tab': [97, 9, 98],
        'formfeed': [97, 12, 98],
        'backspace': [97, 8, 98],
        'nul': [97, 0, 98],
        'high': [97, 0xFF, 98],
      };
      final back = await _roundTrip(
          cases.map((key, value) => MapEntry(key, _chars(value))));

      for (final entry in cases.entries) {
        expect(back[entry.key], orderedEquals(entry.value), reason: entry.key);
      }
    });

    test('the characters that always needed escaping still round trip',
        () async {
      final back = await _roundTrip({
        'paren': _chars([97, 40, 41, 98]),
        'backslash': _chars([97, 92, 98]),
        'unbalanced': _chars([40, 40, 97]),
      });

      expect(back['paren'], orderedEquals([97, 40, 41, 98]));
      expect(back['backslash'], orderedEquals([97, 92, 98]));
      expect(back['unbalanced'], orderedEquals([40, 40, 97]));
    });

    test('a run of carriage returns keeps its length', () async {
      final back = await _roundTrip({
        'v': _chars([13, 13, 13, 10, 13]),
      });

      expect(back['v'], orderedEquals([13, 13, 13, 10, 13]));
    });

    test('hex writing was never affected and stays exact', () async {
      final back = await _roundTrip({'v': _chars([97, 13, 10, 98])}, hex: true);

      expect(back['v'], orderedEquals([97, 13, 10, 98]));
    });
  });
}
