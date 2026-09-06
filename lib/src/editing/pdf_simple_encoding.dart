import 'dart:typed_data';

/// Unicode decoding of unmodified simple-font character encodings.
///
/// Character assignments follow Adobe PDF Reference 1.7, Appendix D.1,
/// pages 997–1000, including notes 3, 5 and 6:
/// https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.7old.pdf
/// This implementation was written from the normative character assignments,
/// independently of other PDF library source code.
///
/// `StandardEncoding` here names the built-in Latin Type1 encoding; it is not
/// a permitted predefined PDF /Encoding name. Font-specific Differences and
/// ToUnicode mappings must be handled by the caller before using this decoder.
abstract final class PdfSimpleEncoding {
  /// Encodes only characters representable by the selected PDF encoding.
  /// No transliteration or replacement glyph is substituted on failure.
  static Uint8List encode(String encoding, String text) {
    // Validate even empty input, consistently with decode.
    decode(encoding, Uint8List(0));
    final inverse = _encoders.putIfAbsent(encoding, () {
      final table = <int, int>{};
      for (var code = 32; code <= 255; code++) {
        try {
          final scalar =
              decode(encoding, Uint8List.fromList([code])).runes.single;
          table.putIfAbsent(scalar, () => code);
        } on FormatException {
          // Undefined bytes are not candidates for encoding.
        }
      }
      // Prefer the ordinary bullet slot over compatibility aliases.
      if (encoding == 'WinAnsiEncoding') table[0x2022] = 0x95;
      return table;
    });
    final bytes = BytesBuilder(copy: false);
    var offset = 0;
    for (final scalar in text.runes) {
      final code = inverse[scalar];
      if (code == null) {
        throw FormatException(
            'Character is not representable in $encoding', text, offset);
      }
      bytes.addByte(code);
      offset += scalar > 0xffff ? 2 : 1;
    }
    return bytes.takeBytes();
  }

  static final _encoders = <String, Map<int, int>>{};

  static String decode(String encoding, Uint8List codes) {
    if (encoding != 'StandardEncoding' && encoding != 'WinAnsiEncoding') {
      throw UnsupportedError('Unsupported simple font encoding: $encoding');
    }
    final result = StringBuffer();
    for (var index = 0; index < codes.length; index++) {
      final code = codes[index];
      int? unicode;
      if (encoding == 'StandardEncoding') {
        unicode = _standardExceptions[code];
        if (unicode == null && code >= 32 && code <= 126) unicode = code;
      } else if (code >= 32) {
        // PDF assigns a bullet to unused high codes, unlike Windows CP1252.
        unicode = _winAnsiExceptions[code] ?? code;
      }
      if (unicode == null) {
        throw FormatException(
            'Undefined $encoding character code 0x${code.toRadixString(16).padLeft(2, '0')}',
            codes,
            index);
      }
      result.writeCharCode(unicode);
    }
    return result.toString();
  }

  static const _standardExceptions = <int, int>{
    0x27: 0x2019,
    0x60: 0x2018,
    0xa1: 0x00a1,
    0xa2: 0x00a2,
    0xa3: 0x00a3,
    0xa4: 0x2044,
    0xa5: 0x00a5,
    0xa6: 0x0192,
    0xa7: 0x00a7,
    0xa8: 0x00a4,
    0xa9: 0x0027,
    0xaa: 0x201c,
    0xab: 0x00ab,
    0xac: 0x2039,
    0xad: 0x203a,
    0xae: 0xfb01,
    0xaf: 0xfb02,
    0xb1: 0x2013,
    0xb2: 0x2020,
    0xb3: 0x2021,
    0xb4: 0x00b7,
    0xb6: 0x00b6,
    0xb7: 0x2022,
    0xb8: 0x201a,
    0xb9: 0x201e,
    0xba: 0x201d,
    0xbb: 0x00bb,
    0xbc: 0x2026,
    0xbd: 0x2030,
    0xbf: 0x00bf,
    0xc1: 0x0060,
    0xc2: 0x00b4,
    0xc3: 0x02c6,
    0xc4: 0x02dc,
    0xc5: 0x00af,
    0xc6: 0x02d8,
    0xc7: 0x02d9,
    0xc8: 0x00a8,
    0xca: 0x02da,
    0xcb: 0x00b8,
    0xcd: 0x02dd,
    0xce: 0x02db,
    0xcf: 0x02c7,
    0xd0: 0x2014,
    0xe1: 0x00c6,
    0xe3: 0x00aa,
    0xe8: 0x0141,
    0xe9: 0x00d8,
    0xea: 0x0152,
    0xeb: 0x00ba,
    0xf1: 0x00e6,
    0xf5: 0x0131,
    0xf8: 0x0142,
    0xf9: 0x00f8,
    0xfa: 0x0153,
    0xfb: 0x00df,
  };

  static const _winAnsiExceptions = <int, int>{
    0x7f: 0x2022,
    0x80: 0x20ac,
    0x81: 0x2022,
    0x82: 0x201a,
    0x83: 0x0192,
    0x84: 0x201e,
    0x85: 0x2026,
    0x86: 0x2020,
    0x87: 0x2021,
    0x88: 0x02c6,
    0x89: 0x2030,
    0x8a: 0x0160,
    0x8b: 0x2039,
    0x8c: 0x0152,
    0x8d: 0x2022,
    0x8e: 0x017d,
    0x8f: 0x2022,
    0x90: 0x2022,
    0x91: 0x2018,
    0x92: 0x2019,
    0x93: 0x201c,
    0x94: 0x201d,
    0x95: 0x2022,
    0x96: 0x2013,
    0x97: 0x2014,
    0x98: 0x02dc,
    0x99: 0x2122,
    0x9a: 0x0161,
    0x9b: 0x203a,
    0x9c: 0x0153,
    0x9d: 0x2022,
    0x9e: 0x017e,
    0x9f: 0x0178,
  };
}
