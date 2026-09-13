import 'package:dpdf/src/io/font/adobe_glyph_list.dart';
import 'package:dpdf/src/io/font/base_encodings.dart';
import 'package:dpdf/src/io/font/font_encoding.dart';
import 'package:test/test.dart';

void main() {
  group('Adobe Glyph List', () {
    test('listed names resolve to their character', () {
      expect(AdobeGlyphList.nameToUnicode('A'), 0x41);
      expect(AdobeGlyphList.nameToUnicode('quoteright'), 0x2019);
      expect(AdobeGlyphList.nameToUnicode('Adieresis'), 0xc4);
      expect(AdobeGlyphList.nameToUnicode('nonesuch'), -1);
      expect(AdobeGlyphList.nameToUnicode(''), -1);
    });

    test('hexadecimal glyph names are decoded when the list has none', () {
      expect(AdobeGlyphList.nameToUnicode('uni20AC'), 0x20ac);
      expect(AdobeGlyphList.nameToUnicode('u20AC'), 0x20ac);
      expect(AdobeGlyphList.nameToUnicode('u1F600'), 0x1f600);
      expect(AdobeGlyphList.nameToUnicode('u10FFFF'), 0x10ffff);
      // A surrogate code unit is not a character and names nothing.
      expect(AdobeGlyphList.nameToUnicode('uniD800'), -1);
      expect(AdobeGlyphList.nameToUnicode('uni20A'), -1);
      expect(AdobeGlyphList.nameToUnicode('u20A'), -1);
    });

    test('a variant suffix is dropped and ligature parts are joined', () {
      expect(AdobeGlyphList.nameToUnicode('a.sc'), 0x61);
      expect(AdobeGlyphList.nameToUnicode('one.oldstyle'), 0x31);
      expect(AdobeGlyphList.nameToUnicodeText('f_f_i'), 'ffi');
      expect(AdobeGlyphList.nameToUnicodeText('uni00660069'), 'fi');
      expect(AdobeGlyphList.nameToUnicodeText('A_uni0301')?.runes.toList(),
          [0x41, 0x301]);
      // A ligature has no single scalar of its own.
      expect(AdobeGlyphList.nameToUnicode('f_i'), -1);
      expect(AdobeGlyphList.nameToUnicodeText('.notdef'), isNull);
      expect(AdobeGlyphList.nameToUnicodeText('g23'), isNull);
    });
  });

  group('/Differences', () {
    test('a code opens a run of consecutive assignments', () {
      // The example of 9.6.6.1, abbreviated.
      final flattened = FontEncoding.flattenDifferences([
        39, 'quotesingle', //
        96, 'grave',
        128, 'Adieresis', 'Aring', 'Ccedilla',
        170, 'trademark',
      ]);
      expect(flattened, {
        39: 'quotesingle',
        96: 'grave',
        128: 'Adieresis',
        129: 'Aring',
        130: 'Ccedilla',
        170: 'trademark',
      });
    });

    test('malformed arrays are rejected instead of guessed at', () {
      expect(
          () => FontEncoding.flattenDifferences(['A']), throwsFormatException);
      expect(() => FontEncoding.flattenDifferences([300, 'A']),
          throwsFormatException);
      expect(() => FontEncoding.flattenDifferences([255, 'A', 'B']),
          throwsFormatException);
      expect(() => FontEncoding.flattenDifferences([65, 'A', 65, 'B']),
          throwsFormatException,
          reason: 'sequences shall not overlap');
      expect(() => FontEncoding.flattenDifferences([65, 3.5]),
          throwsFormatException);
      expect(FontEncoding.flattenDifferences([]), isEmpty);
    });
  });

  group('encoding resolution of 9.6.6.1', () {
    test('a named base encoding fills the whole table', () {
      final encoding =
          FontEncoding.createEncoding(baseEncoding: 'WinAnsiEncoding');
      expect(encoding.getDifference(0x41), 'A');
      expect(encoding.getDifference(0x80), 'Euro');
      expect(encoding.getUnicode(0x80), 0x20ac);
      expect(encoding.convertToByte(0x20ac), 0x80);
      expect(encoding.isFontSpecific(), isFalse);
      // Note 3 shows a bullet at every unassigned code, but only 0x95 is
      // the code that text encoding may use for it.
      expect(encoding.getDifference(0x81), 'bullet');
      expect(encoding.convertToByte(0x2022), 0x95);
      // Notes 5 and 6 duplicate the hyphen and the space.
      expect(encoding.convertToByte(0x20), 0x20);
      expect(encoding.convertToByte(0x2d), 0x2d);
    });

    test('differences override the base and keep the rest of it', () {
      final encoding = FontEncoding.createEncoding(
        baseEncoding: 'MacRomanEncoding',
        differences: FontEncoding.flattenDifferences([39, 'quotesingle']),
      );
      expect(encoding.getDifference(0x27), 'quotesingle');
      expect(encoding.getUnicode(0x27), 0x27);
      expect(encoding.getDifference(0x80), 'Adieresis');
      // The MacRoman quoteright, now unreachable, no longer encodes.
      expect(encoding.convertToByte(0x2019), 0xd5);
    });

    test('an absent base encoding follows the symbolic flag', () {
      final nonsymbolic = FontEncoding.createEncoding();
      expect(nonsymbolic.getDifference(0x41), 'A');
      expect(nonsymbolic.getDifference(0x27), 'quoteright',
          reason: 'StandardEncoding is the implicit base');
      expect(nonsymbolic.isFontSpecific(), isFalse);

      final symbolic = FontEncoding.createEncoding(symbolic: true);
      expect(symbolic.getDifference(0x41), isNull);
      expect(symbolic.isFontSpecific(), isTrue);
    });

    test('an embedded program supplies the implicit base encoding', () {
      final encoding = FontEncoding.createEncoding(
        builtIn: BaseEncodings.symbol,
        symbolic: true,
        differences: FontEncoding.flattenDifferences([0x41, 'Alpha']),
      );
      expect(encoding.getDifference(0x61), 'alpha');
      expect(encoding.getDifference(0x41), 'Alpha');
      expect(encoding.getUnicode(0x61), 0x3b1);
      expect(encoding.isFontSpecific(), isTrue);
    });

    test('9.6.6.4 fills what is left over from StandardEncoding', () {
      final encoding = FontEncoding.createEncoding(
        differences: FontEncoding.flattenDifferences([0x41, 'Alpha']),
        symbolic: true,
        fillUndefinedFromStandard: true,
      );
      expect(encoding.getDifference(0x41), 'Alpha');
      expect(encoding.getDifference(0x42), 'B');
      expect(encoding.getDifference(0x27), 'quoteright');
      expect(encoding.getDifference(0x10), isNull);
    });
  });

  test('assigning one difference keeps the Unicode mappings in step', () {
    final encoding = FontEncoding.createFontEncoding('WinAnsiEncoding');
    expect(encoding.convertToByte(0x41), 0x41);
    encoding.setDifference(0x41, 'Alpha');
    expect(encoding.getDifference(0x41), 'Alpha');
    expect(encoding.getUnicode(0x41), 0x391);
    expect(encoding.convertToByte(0x391), 0x41);
    expect(encoding.canEncode(0x41), isFalse,
        reason: 'no code shows the letter A any more');
    expect(encoding.getUnicodeDifference(0x391), 0x41);
    encoding.setDifference(0x41, 'A');
    expect(encoding.getUnicode(0x41), 0x41);
    expect(encoding.convertToByte(0x41), 0x41);
  });

  group('named encodings built through createFontEncoding', () {
    test('the predefined Latin encodings decode their own bytes', () {
      for (final name in [
        'WinAnsiEncoding',
        'MacRomanEncoding',
        'StandardEncoding',
        'MacExpertEncoding',
      ]) {
        final encoding = FontEncoding.createFontEncoding(name);
        final table = BaseEncodings.byName(name)!;
        for (var code = 0; code < 256; code++) {
          expect(encoding.getDifference(code), table[code],
              reason: '$name code $code');
        }
      }
    });

    test('the symbol sets report themselves as font specific', () {
      final symbol = FontEncoding.createFontEncoding('Symbol');
      expect(symbol.isFontSpecific(), isTrue);
      expect(symbol.getDifference(0x61), 'alpha');
      expect(symbol.getUnicode(0x61), 0x3b1);

      final dingbats = FontEncoding.createFontEncoding('ZapfDingbatsEncoding');
      expect(dingbats.isFontSpecific(), isTrue);
      expect(dingbats.getDifference(0x21), 'a1');
    });

    test('round trip through convertToBytes preserves representable text', () {
      final encoding = FontEncoding.createFontEncoding('WinAnsiEncoding');
      final bytes = encoding.convertToBytes('Olá, € 5–');
      expect(bytes, [79, 108, 0xe1, 44, 32, 0x80, 32, 53, 0x96]);
    });
  });

  group('custom encodings', () {
    test('a simple form assigns consecutive codes to scalars', () {
      final encoding = FontEncoding.createFontEncoding('#simple 65 41 42 43');
      expect(encoding.getDifference(65), 'A');
      expect(encoding.getDifference(66), 'B');
      expect(encoding.getDifference(67), 'C');
      expect(encoding.getDifference(68), FontEncoding.NOTDEF);
      expect(encoding.convertToByte(0x43), 67);
      expect(encoding.getUnicode(65), 0x41);
    });

    test('a full form names each glyph and may quote its code', () {
      final encoding =
          FontEncoding.createFontEncoding("#full 'a alpha 03B1, 66 beta 03B2");
      expect(encoding.getDifference(0x61), 'alpha');
      expect(encoding.getDifference(66), 'beta');
      expect(encoding.getUnicode(0x61), 0x3b1);
      expect(encoding.convertToByte(0x3b2), 66);
    });

    test('a malformed custom encoding is reported, never half applied', () {
      expect(() => FontEncoding.createFontEncoding('#'), throwsFormatException);
      expect(() => FontEncoding.createFontEncoding('#weird 32 41'),
          throwsFormatException);
      expect(() => FontEncoding.createFontEncoding('#full 65 A'),
          throwsFormatException);
      expect(() => FontEncoding.createFontEncoding('#simple 300 41'),
          throwsFormatException);
      expect(() => FontEncoding.createFontEncoding('#simple 65 D800'),
          throwsFormatException);
      expect(() => FontEncoding.createFontEncoding('#simple 254 41 42 43'),
          throwsFormatException);
    });
  });
}
