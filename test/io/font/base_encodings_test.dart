import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/io/font/adobe_glyph_list.dart';
import 'package:dpdf/src/io/font/base_encodings.dart';
import 'package:dpdf/src/editing/pdf_simple_encoding.dart';
import 'package:dpdf/src/io/font/pdf_encodings.dart';
import 'package:dpdf/src/io/resources/embedded_font_resources.dart';
import 'package:test/test.dart';

/// The built-in encoding of a standard face, read from the metrics this
/// package embeds: every `C` field of an AFM character record is the code
/// the font's own encoding assigns to the glyph named by its `N` field.
Map<int, String> _builtInEncoding(String face) {
  final metrics = EmbeddedFontResources.metrics(face);
  expect(metrics, isNotNull, reason: face);
  final result = <int, String>{};
  for (final line in const LineSplitter().convert(latin1.decode(metrics!))) {
    if (!line.startsWith('C ')) continue;
    final fields = <String, String>{};
    for (final part in line.split(';')) {
      final text = part.trim();
      if (text.isEmpty) continue;
      final space = text.indexOf(' ');
      if (space > 0)
        fields[text.substring(0, space)] = text.substring(space + 1);
    }
    final code = int.parse(fields['C']!);
    if (code >= 0 && code < 256) result[code] = fields['N']!;
  }
  return result;
}

void main() {
  test('every table covers the whole byte range exactly once', () {
    for (final name in [
      BaseEncodings.standardEncoding,
      BaseEncodings.winAnsiEncoding,
      BaseEncodings.macRomanEncoding,
      BaseEncodings.macExpertEncoding,
      BaseEncodings.pdfDocEncoding,
      BaseEncodings.symbolEncoding,
      BaseEncodings.zapfDingbatsEncoding,
      BaseEncodings.macOsRomanEncoding,
    ]) {
      final table = BaseEncodings.byName(name);
      expect(table, isNotNull, reason: name);
      expect(table!.length, 256, reason: name);
      expect(() => table[0] = 'x', throwsUnsupportedError, reason: name);
      // No code below 0x18 is ever assigned a glyph; PDFDocEncoding is
      // alone in reaching below the space, for its eight diacritics.
      expect(table.sublist(0, 0x18), everyElement(isNull), reason: name);
      if (name != BaseEncodings.pdfDocEncoding) {
        expect(table.sublist(0x18, 0x20), everyElement(isNull), reason: name);
      }
    }
  });

  test('StandardEncoding is the built-in encoding of the Latin faces', () {
    final helvetica = _builtInEncoding('Helvetica');
    final table = BaseEncodings.standard;
    expect(helvetica.length, 149);
    for (var code = 0; code < 256; code++) {
      expect(table[code], helvetica[code], reason: 'code $code');
    }
    // The same encoding serves every Latin face this package embeds.
    for (final face in ['Courier', 'Times-Roman', 'Helvetica-BoldOblique']) {
      expect(_builtInEncoding(face), helvetica, reason: face);
    }
  });

  test('the symbol sets are the built-in encodings of their faces', () {
    final symbol = _builtInEncoding('Symbol');
    final dingbats = _builtInEncoding('ZapfDingbats');
    for (var code = 0; code < 256; code++) {
      expect(BaseEncodings.symbol[code], symbol[code], reason: 'symbol $code');
      expect(BaseEncodings.zapfDingbats[code], dingbats[code],
          reason: 'dingbats $code');
    }
    expect(BaseEncodings.symbol[0x61], 'alpha');
    expect(BaseEncodings.symbol[0xd6], 'radical');
    expect(BaseEncodings.zapfDingbats[0x21], 'a1');
    expect(BaseEncodings.zapfDingbats[0xfe], 'a191');
  });

  test('WinAnsiEncoding agrees with the byte-to-character table', () {
    final table = BaseEncodings.winAnsi;
    for (var code = 0x20; code < 256; code++) {
      final name = table[code];
      expect(name, isNotNull, reason: 'code $code');
      // Note 3: every code above the space shows something, and the codes
      // the standard leaves unassigned show a bullet.
      // Code 0x7F is the Windows delete control, which WinAnsiEncoding
      // leaves unassigned and so shows as a bullet like any other.
      final scalar =
          code == 0x7f ? 65533 : PdfEncodings.winansiByteToChar[code];
      if (scalar == 65533) {
        expect(name, 'bullet', reason: 'unassigned code $code');
        continue;
      }
      // Notes 5 and 6 give the soft hyphen and the non-breaking space the
      // names of the ordinary hyphen and space, which the byte-to-character
      // table keeps apart because it decodes to Unicode rather than to a
      // glyph.
      if (code == 0xa0 || code == 0xad) {
        expect(name, code == 0xa0 ? 'space' : 'hyphen');
        continue;
      }
      // The list gives "mu" the Greek letter of the Symbol font; Latin text
      // uses the same name for the micro sign.
      final expected =
          name == 'mu' ? 0xb5 : AdobeGlyphList.nameToUnicode(name!);
      expect(expected, scalar, reason: 'code $code named $name');
    }
    expect(table[0x80], 'Euro');
    expect(table[0x95], 'bullet');
    expect(table[0xa0], 'space', reason: 'note 6, non-breaking space');
    expect(table[0xad], 'hyphen', reason: 'note 5, soft hyphen');
  });

  test('PDFDocEncoding agrees with the text-string decoder', () {
    final table = BaseEncodings.pdfDoc;
    for (var code = 0; code < 256; code++) {
      final decoded = PdfEncodings.convertToString(
          Uint8List.fromList([code]), PdfEncodings.PDF_DOC_ENCODING);
      final name = table[code];
      if (decoded == '�' || code < 0x18) {
        // The three whitespace controls have no glyph name of their own.
        expect(name, isNull, reason: 'code $code');
        continue;
      }
      final expected =
          name == 'mu' ? 0xb5 : AdobeGlyphList.nameToUnicode(name!);
      expect(expected, decoded.runes.single, reason: 'code $code named $name');
    }
    expect(table[0x18], 'breve');
    expect(table[0xa0], 'Euro');
  });

  test('MacRomanEncoding and MacExpertEncoding hold their landmarks', () {
    expect(BaseEncodings.macRoman[0x80], 'Adieresis');
    expect(BaseEncodings.macRoman[0xa5], 'bullet');
    expect(BaseEncodings.macRoman[0xca], 'space', reason: 'note 6');
    expect(BaseEncodings.macRoman[0xdb], 'currency', reason: 'note 1');
    expect(BaseEncodings.macRoman[0xf0], isNull, reason: 'the Apple logo');
    expect(BaseEncodings.macExpert[0x21], 'exclamsmall');
    expect(BaseEncodings.macExpert[0x56], 'ff');
    expect(BaseEncodings.macExpert[0xbe], 'AEsmall');
    expect(BaseEncodings.macExpert[0xfb], 'Ringsmall');
    // The expert set shares only punctuation and ligatures with the Latin
    // set; every letter and digit in it is a small capital or an old style.
    final latin = BaseEncodings.standard.whereType<String>().toSet();
    final expert = BaseEncodings.macExpert.whereType<String>().toSet();
    expect(latin.intersection(expert), {
      'space',
      'comma',
      'hyphen',
      'period',
      'fraction',
      'colon',
      'semicolon',
      'fi',
      'fl'
    });
  });

  test('the Latin tables agree with the simple font decoder', () {
    // A second reading of Annex D lives in the text extraction code, which
    // decodes bytes to Unicode instead of naming glyphs. Where both know a
    // code, they have to agree.
    for (final pair in {
      BaseEncodings.standardEncoding: BaseEncodings.standard,
      BaseEncodings.macRomanEncoding: BaseEncodings.macRoman,
    }.entries) {
      for (var code = 0; code < 256; code++) {
        final name = pair.value[code];
        String? decoded;
        try {
          decoded =
              PdfSimpleEncoding.decode(pair.key, Uint8List.fromList([code]));
        } on FormatException {
          decoded = null;
        }
        if (name == null || decoded == null) continue;
        // The non-breaking space of note 6 decodes as itself.
        if (pair.key == BaseEncodings.macRomanEncoding && code == 0xca) {
          continue;
        }
        final expected =
            name == 'mu' ? 0xb5 : AdobeGlyphList.nameToUnicode(name);
        expect(expected, decoded.runes.single,
            reason: '${pair.key} code $code named $name');
      }
    }
  });

  test('Mac OS Roman adds exactly the sixteen codes of Table 115', () {
    final differences = <int, String>{};
    for (var code = 0; code < 256; code++) {
      final mac = BaseEncodings.macRoman[code];
      final macOs = BaseEncodings.macOsRoman[code];
      if (mac != macOs) differences[code] = macOs!;
    }
    expect(differences, {
      0xad: 'notequal',
      0xb0: 'infinity',
      0xb2: 'lessequal',
      0xb3: 'greaterequal',
      0xb6: 'partialdiff',
      0xb7: 'summation',
      0xb8: 'product',
      0xb9: 'pi',
      0xba: 'integral',
      0xbd: 'Omega',
      0xc3: 'radical',
      0xc5: 'approxequal',
      0xc6: 'Delta',
      0xd7: 'lozenge',
      0xdb: 'Euro',
      0xf0: 'apple',
    });
    // The reverse lookup of 9.6.6.4 prefers the code the standard names.
    expect(BaseEncodings.macOsRomanCode('space'), 0x20);
    expect(BaseEncodings.macOsRomanCode('notequal'), 0xad);
    expect(BaseEncodings.macOsRomanCode('Adieresis'), 0x80);
    expect(BaseEncodings.macOsRomanCode('currency'), isNull);
  });

  test('the Macintosh glyph ordering has its standard 258 names', () {
    final order = BaseEncodings.macGlyphOrder;
    expect(order.length, 258);
    expect(order.take(4), ['.notdef', '.null', 'nonmarkingreturn', 'space']);
    expect(order[97], 'asciitilde');
    expect(order[98], 'Adieresis');
    expect(order[172], 'nonbreakingspace');
    expect(order[189], 'currency');
    expect(order[210], 'apple');
    expect(order[226], 'Lslash');
    expect(order.last, 'dcroat');
    expect(order.toSet().length, 258, reason: 'no name is repeated');
  });

  test('encoding names are recognised in the spellings PDF uses', () {
    expect(BaseEncodings.canonicalName('WinAnsiEncoding'),
        BaseEncodings.winAnsiEncoding);
    expect(BaseEncodings.canonicalName('Windows-1252'),
        BaseEncodings.winAnsiEncoding);
    expect(BaseEncodings.canonicalName('MacRoman'),
        BaseEncodings.macRomanEncoding);
    expect(BaseEncodings.canonicalName('pdf'), BaseEncodings.pdfDocEncoding);
    expect(BaseEncodings.canonicalName('UTF-8'), isNull);
    expect(BaseEncodings.byName('Nonesuch'), isNull);
    expect(BaseEncodings.predefinedNames,
        {'WinAnsiEncoding', 'MacRomanEncoding', 'MacExpertEncoding'});
  });
}
