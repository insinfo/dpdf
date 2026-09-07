import 'dart:typed_data';
import 'package:dpdf/src/io/font/adobe_glyph_list.dart';
import 'package:dpdf/src/io/font/constants/font_weights.dart';

import 'package:dpdf/src/io/font/font_program.dart';

import 'package:dpdf/src/io/font/otf/glyph.dart';
import 'package:dpdf/src/io/font/type1_parser.dart';

class CraftType1Font extends CraftFontProgram {
  static final List<int> PFB_TYPES = [1, 2, 1];

  CraftType1Parser? fontParser;
  String? characterSet;
  Map<(int, int), int> kernPairs = {};
  Uint8List? fontStreamBytes;
  List<int>? fontStreamLengths;

  CraftType1Font(
      String metricsPath, String binaryPath, Uint8List? afm, Uint8List? pfb) {
    fontParser = CraftType1Parser(metricsPath, binaryPath, afm, pfb);
    loadAfmMetrics();
  }

  static CraftType1Font createBuiltInFont(String fontName) {
    return CraftType1Font(fontName, "", null, null);
  }

  @override
  int getPdfFontFlags() {
    int flags = 0;
    if (fontMetrics.getIsFixedPitch()) {
      flags |= 1;
    }
    flags |= getIsFontSpecific() ? 4 : 32;
    if (fontMetrics.getItalicAngle() < 0) {
      flags |= 64;
    }
    String? fontName = fontNames.getFontName();
    if (fontName != null &&
        (fontName.contains("Caps") || fontName.endsWith("SC"))) {
      flags |= 131072;
    }
    if (fontNames.isBold() || fontNames.getFontWeight() > 500) {
      flags |= 262144;
    }
    return flags;
  }

  @override
  bool hasKernPairs() => kernPairs.isNotEmpty;

  @override
  int getKerningByGlyph(CraftGlyph first, CraftGlyph second) {
    if (first.hasValidUnicode() && second.hasValidUnicode()) {
      final record = (first.getUnicode(), second.getUnicode());
      if (kernPairs.containsKey(record)) {
        return kernPairs[record]!;
      }
    }
    return 0;
  }

  // Implementation of abstract getKerning(int, int) is in FontProgram

  void loadAfmMetrics() {
    final input = fontParser?.getMetricsFile();
    if (input == null) return;
    var section = 'header';
    var sawCharacters = false;
    var completed = false;
    var expected = 0;
    var consumed = 0;
    var widthTotal = 0;
    var glyphCount = 0;
    final byCode = <int, CraftGlyph>{};
    final byUnicode = <int, CraftGlyph>{};
    final pairs = <(int, int), int>{};
    final header = <String, void Function(String)>{
      'FontName': fontNames.setFontName,
      'FullName': fontNames.setFullNameString,
      'FamilyName': fontNames.setFamilyNameString,
      'CharacterSet': (text) => characterSet = text,
      'EncodingScheme': (text) => encodingScheme = text,
      'Weight': (text) =>
          fontNames.setFontWeight(CraftFontWeights.fromType1FontWeight(text)),
      'ItalicAngle': (text) => fontMetrics.setItalicAngle(double.parse(text)),
      'IsFixedPitch': (text) {
        if (text != 'true' && text != 'false') {
          throw FormatException('AFM pitch flag must be boolean.');
        }
        fontMetrics.setIsFixedPitch(text == 'true');
      },
      'FontBBox': (text) {
        final coordinates = _afmNumbers(text, 4);
        fontMetrics.setBbox(
            coordinates[0], coordinates[1], coordinates[2], coordinates[3]);
      },
    };
    final metric = <String, void Function(int)>{
      'CapHeight': fontMetrics.setCapHeight,
      'XHeight': fontMetrics.setXHeight,
      'Ascender': fontMetrics.setTypoAscender,
      'Descender': fontMetrics.setTypoDescender,
      'StdHW': fontMetrics.setStemH,
      'StdVW': fontMetrics.setStemV,
      'UnderlinePosition': fontMetrics.setUnderlinePosition,
      'UnderlineThickness': fontMetrics.setUnderlineThickness,
    };
    try {
      String? line;
      while ((line = input.readLine()) != null) {
        final row = _afmRecord(line!);
        if (row == null || row.$1 == 'Comment') continue;
        final (keyword, payload) = row;
        if (section == 'glyphs') {
          if (keyword == 'EndCharMetrics') {
            if (consumed != expected) {
              throw FormatException(
                  'AFM character count does not match its section.');
            }
            section = 'tail';
            continue;
          }
          final glyph = _afmGlyph(line);
          if (glyph.getCode() >= 0) byCode[glyph.getCode()] = glyph;
          if (glyph.hasValidUnicode()) byUnicode[glyph.getUnicode()] = glyph;
          widthTotal += glyph.getWidth();
          glyphCount++;
          consumed++;
          continue;
        }
        if (section == 'kerning') {
          if (keyword == 'EndKernPairs') {
            if (consumed != expected) {
              throw FormatException(
                  'AFM kerning count does not match its section.');
            }
            section = 'tail';
            continue;
          }
          if (keyword == 'KPX') {
            final values = payload.split(RegExp(r'\s+'));
            if (values.length != 3) {
              throw FormatException(
                  'AFM horizontal kerning needs two names and an adjustment.');
            }
            final first = CraftAdobeGlyphList.nameToUnicode(values[0]);
            final second = CraftAdobeGlyphList.nameToUnicode(values[1]);
            final adjustment = _afmNumbers(values[2], 1).single;
            if (first >= 0 && second >= 0) pairs[(first, second)] = adjustment;
          }
          consumed++;
          continue;
        }
        if (keyword == 'StartCharMetrics') {
          if (sawCharacters) {
            throw FormatException('AFM character metrics section is repeated.');
          }
          sawCharacters = true;
          section = 'glyphs';
          expected = int.parse(payload);
          consumed = 0;
        } else if (keyword == 'StartKernPairs' ||
            keyword == 'StartKernPairs0') {
          section = 'kerning';
          expected = int.parse(payload);
          consumed = 0;
        } else if (keyword == 'EndFontMetrics') {
          completed = true;
          break;
        } else if (section == 'header') {
          if (metric.containsKey(keyword)) {
            metric[keyword]!(_afmNumbers(payload, 1).single);
          } else {
            header[keyword]?.call(payload);
          }
        }
        if (expected < 0) {
          throw FormatException('AFM section count cannot be negative.');
        }
      }
      if (!sawCharacters ||
          !completed ||
          section == 'glyphs' ||
          section == 'kerning') {
        throw FormatException('AFM metrics program has an incomplete section.');
      }
    } finally {
      input.close();
    }
    final space = byUnicode[32];
    if (space != null) {
      byUnicode.putIfAbsent(
          160,
          () => CraftGlyph(
              space.getCode(), space.getWidth(), 160, space.getBbox()));
    }
    codeToGlyph
      ..clear()
      ..addAll(byCode);
    unicodeToGlyph
      ..clear()
      ..addAll(byUnicode);
    kernPairs = pairs;
    avgWidth = glyphCount == 0 ? 0 : widthTotal ~/ glyphCount;
    isFontSpecific = !const {'AdobeStandardEncoding', 'StandardEncoding'}
        .contains(encodingScheme);
  }

  static (String, String)? _afmRecord(String source) {
    final row = source.trim();
    if (row.isEmpty) return null;
    final separator = row.indexOf(RegExp(r'\s'));
    return separator < 0
        ? (row, '')
        : (row.substring(0, separator), row.substring(separator).trim());
  }

  static List<int> _afmNumbers(String text, int count) {
    final tokens = text.trim().split(RegExp(r'[\s,]+'));
    if (tokens.length != count) {
      throw FormatException('AFM numeric field requires $count values.');
    }
    return tokens.map((token) {
      final value = double.parse(token);
      if (!value.isFinite) throw FormatException('AFM metric must be finite.');
      return value.toInt();
    }).toList();
  }

  static CraftGlyph _afmGlyph(String row) {
    final fields = <String, String>{};
    for (final part in row.split(';')) {
      final record = _afmRecord(part);
      if (record != null) fields[record.$1] = record.$2;
    }
    var code = -1;
    if (fields.containsKey('C')) code = int.parse(fields['C']!);
    if (fields.containsKey('CH')) {
      final value = fields['CH']!;
      if (!RegExp(r'^<[0-9A-Fa-f]+>$').hasMatch(value)) {
        throw FormatException('AFM hexadecimal character code is malformed.');
      }
      code = int.parse(value.substring(1, value.length - 1), radix: 16);
    }
    final advance = fields['WX'] ?? fields['W0X'];
    final width = advance != null
        ? _afmNumbers(advance, 1).single
        : fields.containsKey('W')
            ? _afmNumbers(fields['W']!, 2).first
            : 250;
    final bounds =
        fields.containsKey('B') ? _afmNumbers(fields['B']!, 4) : null;
    final unicode = CraftAdobeGlyphList.nameToUnicode(fields['N'] ?? '');
    return CraftGlyph(code, width, unicode, bounds);
  }

  Uint8List? getFontStreamBytes() {
    if (fontStreamBytes == null && fontParser != null) {
      try {
        Uint8List pfb = fontParser!.getPostscriptBinary().getBytes();
        // Parse PFB segments
        List<int> out = [];
        fontStreamLengths = [];
        int ptr = 0;
        while (ptr < pfb.length) {
          if (pfb[ptr++] != 0x80) break;
          int type = pfb[ptr++];
          if (type == 3) break; // EOF segment
          int len = (pfb[ptr++] & 0xFF) |
              ((pfb[ptr++] & 0xFF) << 8) |
              ((pfb[ptr++] & 0xFF) << 16) |
              ((pfb[ptr++] & 0xFF) << 24);
          fontStreamLengths!.add(len);
          if (ptr + len > pfb.length) len = pfb.length - ptr;
          out.addAll(pfb.sublist(ptr, ptr + len));
          ptr += len;
        }
        fontStreamBytes = Uint8List.fromList(out);
      } catch (e) {
        // PFB might not be available
      }
    }
    return fontStreamBytes;
  }

  bool isBuiltInFont() {
    return fontParser?.isBuiltInFont() ?? false;
  }
}
