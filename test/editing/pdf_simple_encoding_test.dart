import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/editing/pdf_simple_encoding.dart';
import 'package:test/test.dart';

void main() {
  test('Encoding preserves supported text without lossy substitution', () {
    for (final encoding in ['StandardEncoding', 'WinAnsiEncoding']) {
      for (var code = 32; code < 256; code++) {
        String text;
        try {
          text = PdfSimpleEncoding.decode(encoding, Uint8List.fromList([code]));
        } on FormatException {
          continue;
        }
        expect(
            PdfSimpleEncoding.decode(
                encoding, PdfSimpleEncoding.encode(encoding, text)),
            text);
      }
    }
    expect(PdfSimpleEncoding.encode('WinAnsiEncoding', '•'), [0x95]);
    expect(PdfSimpleEncoding.encode('WinAnsiEncoding', 'ação'),
        [0x61, 0xe7, 0xe3, 0x6f]);
    expect(() => PdfSimpleEncoding.encode('StandardEncoding', 'ação'),
        throwsFormatException);
    expect(() => PdfSimpleEncoding.encode('WinAnsiEncoding', 'A😀'),
        throwsA(isA<FormatException>().having((e) => e.offset, 'offset', 1)));
    expect(() => PdfSimpleEncoding.encode('UTF-8', ''), throwsUnsupportedError);
  });
  String decode(String name, List<int> bytes) =>
      PdfSimpleEncoding.decode(name, Uint8List.fromList(bytes));

  test('WinAnsi preserves Portuguese text and Latin1 accents', () {
    const text = 'Criação, edição, ação: João e Luís, à noite.';
    expect(decode('WinAnsiEncoding', latin1.encode(text)), text);
  });

  test('StandardEncoding quotes are not ASCII apostrophe and grave', () {
    expect(decode('StandardEncoding', [0x27, 0x60, 0xa9, 0xc1]), '’‘\'`');
    expect(decode('WinAnsiEncoding', [0x27, 0x60]), '\'`');
  });

  test('StandardEncoding ligatures and accents have explicit mappings', () {
    expect(decode('StandardEncoding', [0xae, 0xaf, 0xe8, 0xfa, 0xc6, 0xcf]),
        '\ufb01\ufb02Łœ˘ˇ');
  });

  test('WinAnsi punctuation includes PDF bullet aliases', () {
    expect(decode('WinAnsiEncoding', [0x80, 0x93, 0x94, 0x96, 0x9c]), '€“”–œ');
    expect(decode('WinAnsiEncoding', [0x7f, 0x81, 0x8d, 0x8f, 0x90, 0x9d]),
        '••••••');
    expect(decode('WinAnsiEncoding', [0xa0, 0xad]), '\u00a0\u00ad');
  });

  test('undefined codes reject instead of replacing or dropping text', () {
    for (final code in [0, 9, 31, 127, 128, 160, 176, 255]) {
      expect(() => decode('StandardEncoding', [65, code]),
          throwsA(isA<FormatException>().having((e) => e.offset, 'offset', 1)));
    }
    expect(() => decode('WinAnsiEncoding', [31]), throwsFormatException);
    expect(() => decode('UTF-8', []), throwsUnsupportedError);
    expect(decode('WinAnsiEncoding', []), isEmpty);
  });
}
