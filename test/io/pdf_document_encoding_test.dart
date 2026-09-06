import 'dart:typed_data';
import 'package:pdfcraft/src/io/font/pdf_encodings.dart';
import 'package:test/test.dart';

void main() {
  const encoding = CraftPdfEncodings.PDF_DOC_ENCODING;
  String decode(List<int> bytes) =>
      CraftPdfEncodings.convertToString(Uint8List.fromList(bytes), encoding);
  Uint8List encode(String text) =>
      CraftPdfEncodings.convertToBytes(text, encoding);

  test('PDF document character assignments differ from Windows ANSI', () {
    expect(decode([0x80, 0x84, 0x8a, 0x93, 0x94, 0x96, 0xa0]),
        '\u2022\u2014\u2212\ufb01\ufb02\u0152\u20ac');
    expect(encode('\u2022\u2014\u2212\ufb01\ufb02\u0152\u20ac'),
        [0x80, 0x84, 0x8a, 0x93, 0x94, 0x96, 0xa0]);
    expect(
        CraftPdfEncodings.convertToString(
            Uint8List.fromList([0x80]), CraftPdfEncodings.WINANSI),
        '\u20ac');
  });

  test('PDF spacing diacritics have their own low byte assignments', () {
    const text = '\u02d8\u02c7\u02c6\u02d9\u02dd\u02db\u02da\u02dc';
    expect(decode(List.generate(8, (i) => i + 24)), text);
    expect(encode(text), List.generate(8, (i) => i + 24));
  });

  test('all defined bytes round trip, undefined bytes produce replacement', () {
    final undefined = {...List.generate(24, (i) => i)}..removeAll([9, 10, 13]);
    undefined.addAll([0x7f, 0x9f, 0xad]);
    for (var byte = 0; byte < 256; byte++) {
      final text = decode([byte]);
      if (undefined.contains(byte)) {
        expect(text, '\ufffd', reason: 'undefined byte $byte');
      } else {
        expect(encode(text), [byte], reason: 'defined byte $byte');
      }
    }
  });

  test('unrepresentable scalars are rejected without low byte truncation', () {
    for (final text in [
      '\u00a0',
      '\u00ad',
      '\u007f',
      '\u0000',
      '\ufffd',
      '\u{1f600}',
      '\u4e2d'
    ]) {
      expect(() => encode(text), throwsFormatException, reason: text);
    }
  });

  test('ASCII, Latin letters and valid whitespace are preserved', () {
    const text = 'Nome: Jo\u00e3o\t\u00e9\r\n';
    expect(decode(encode(text)), text);
    expect(CraftPdfEncodings.convertToString(encode(text), 'pdf'), text);
    expect(encode(''), isEmpty);
  });

  test('UTF encodings and raw bytes remain independent of PDF encoding', () {
    const text = '\u{1f600}\u4e2d';
    for (final encoding in [
      CraftPdfEncodings.UTF8,
      CraftPdfEncodings.UNICODE_BIG,
      CraftPdfEncodings.UNICODE_BIG_UNMARKED
    ]) {
      expect(
          CraftPdfEncodings.convertToString(
              CraftPdfEncodings.convertToBytes(text, encoding), encoding),
          text);
    }
    expect(
        CraftPdfEncodings.convertToString(
            Uint8List.fromList([0x80, 0xad]), null),
        '\u0080\u00ad');
  });
}
