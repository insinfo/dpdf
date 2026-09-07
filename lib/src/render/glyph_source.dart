import 'dart:typed_data';

import 'package:dgfx/dgfx.dart';

import '../editing/pdf_simple_encoding.dart';
import '../editing/pdf_standard_font_metrics.dart';
import '../io/font/adobe_glyph_list.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';

/// What the renderer needs a substitute font for.
class PdfFontRequest {
  /// The `/BaseFont` name from the PDF, e.g. `Helvetica-Bold` or
  /// `ABCDEF+Arial`. The six-letter subset prefix, when present, is kept:
  /// a caller may want it, and stripping it is one line.
  final String baseFont;

  /// `/Flags` from the font descriptor, or 0 when there is none. Bit 1 is
  /// fixed pitch, bit 2 serif, bit 3 symbolic, bit 7 italic; bit 19 (0x40000)
  /// marks bold.
  final int flags;

  /// True for a Type0 font, whose codes index CIDs rather than bytes.
  final bool composite;

  const PdfFontRequest({
    required this.baseFont,
    required this.flags,
    required this.composite,
  });

  /// `/BaseFont` without the `ABCDEF+` subset prefix.
  String get familyName => baseFont.length > 7 && baseFont[6] == '+'
      ? baseFont.substring(7)
      : baseFont;

  bool get isBold => (flags & 0x40000) != 0 || familyName.contains('Bold');
  bool get isItalic =>
      (flags & 0x40) != 0 ||
      familyName.contains('Italic') ||
      familyName.contains('Oblique');
  bool get isSerif => (flags & 2) != 0;
  bool get isFixedPitch => (flags & 1) != 0;

  @override
  String toString() => 'PdfFontRequest($baseFont, flags: $flags)';
}

/// Supplies the bytes of a font to draw with when the PDF embeds none.
///
/// A PDF may reference a font without carrying it, expecting the reader to
/// have it. This package bundles no typefaces — that would be a licensing
/// decision imposed on every user, for megabytes most do not need — so a
/// caller that wants such text drawn provides the font here. Return `null` to
/// leave the text undrawn and reported.
typedef PdfFontFallback = Future<Uint8List?> Function(PdfFontRequest request);

/// Why a font could not be drawn, for the render report.
enum PdfGlyphFailure {
  /// The font dictionary has no embedded program. Drawing it would mean
  /// substituting a different typeface, which changes the page.
  notEmbedded,

  /// There is a program, but it is not sfnt-shaped (Type1/CFF-only), or it
  /// failed to parse.
  unreadableProgram,

  /// A composite font whose `/Encoding` CMap is not one this can decode.
  unsupportedCMap,
}

/// One font from a page's `/Resources`, resolved to what a renderer needs: the
/// outlines to draw, and the advances to place them by.
///
/// Widths come from the PDF, never from the embedded program. The two can
/// disagree, and when they do the PDF is what the producer laid the page out
/// against — following the program instead would shift every glyph after the
/// first. Outlines, on the other hand, can only come from the program.
class PdfGlyphSource {
  /// The parsed font program, or null when there is nothing drawable.
  final BLFontFace? face;

  /// Why [face] is null. Null when the font resolved cleanly.
  final PdfGlyphFailure? failure;

  /// True for Type0 fonts, whose codes are multi-byte and index CIDs.
  final bool composite;

  /// Width per character code, in glyph space (1/1000 of a text unit).
  final Map<int, double> _widths;
  final double _defaultWidth;

  /// For simple fonts: character code to Unicode scalar, from the font's
  /// encoding plus any `/Differences`.
  final Map<int, int> _codeToUnicode;

  /// For composite fonts: CID to glyph index, when `/CIDToGIDMap` is a stream.
  /// Null means the identity mapping.
  final Uint16List? _cidToGid;

  final Map<int, int?> _glyphCache = <int, int?>{};

  PdfGlyphSource._({
    required this.face,
    required this.failure,
    required this.composite,
    required Map<int, double> widths,
    required double defaultWidth,
    required Map<int, int> codeToUnicode,
    required Uint16List? cidToGid,
  })  : _widths = widths,
        _defaultWidth = defaultWidth,
        _codeToUnicode = codeToUnicode,
        _cidToGid = cidToGid;

  /// True when glyphs can actually be drawn.
  bool get isDrawable => face != null;

  /// Splits a PDF string's bytes into character codes.
  ///
  /// Simple fonts are one byte per code. Composite fonts here are two, which
  /// covers Identity-H and Identity-V; a font with a different CMap never gets
  /// this far, because [resolve] refuses it rather than decode it wrongly.
  List<int> codes(Uint8List bytes) {
    if (!composite) return bytes;
    final out = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      out.add((bytes[i] << 8) | bytes[i + 1]);
    }
    // An odd trailing byte is malformed; keeping it as a code is closer to
    // what viewers do than dropping the glyph silently.
    if (bytes.length.isOdd) out.add(bytes.last);
    return out;
  }

  /// Advance for [code], in text space units (already divided by 1000).
  double width(int code) => (_widths[code] ?? _defaultWidth) / 1000.0;

  /// Glyph index for [code], or null when the program has no glyph for it.
  int? glyph(int code) {
    if (face == null) return null;
    return _glyphCache.putIfAbsent(code, () => _resolveGlyph(code));
  }

  int? _resolveGlyph(int code) {
    final font = face!;
    if (composite) {
      // With Identity-H the code is the CID. `/CIDToGIDMap` then says which
      // glyph in the program that CID is.
      final map = _cidToGid;
      if (map == null) return code;
      return code < map.length ? map[code] : 0;
    }

    final unicode = _codeToUnicode[code];
    if (unicode != null) {
      final gid = font.mapCodePoint(unicode);
      if (gid != 0) return gid;
    }

    // Symbolic TrueType fonts commonly map their codes into the (3,0) cmap
    // range at 0xF000 rather than to real Unicode.
    final symbolic = font.mapCodePoint(0xF000 + code);
    if (symbolic != 0) return symbolic;

    final direct = font.mapCodePoint(code);
    return direct != 0 ? direct : null;
  }

  /// Resolves the `/Font` entry named [name] in [resources].
  static Future<PdfGlyphSource?> resolve(
    CraftPdfDictionary? resources,
    String name, {
    PdfFontFallback? fallback,
  }) async {
    final fonts = await resources?.dictionaryEntry(CraftPdfName('Font'));
    final font = await fonts?.dictionaryEntry(CraftPdfName(name));
    if (font == null) return null;

    final subtype = (await font.nameEntry(CraftPdfName.subtype))?.getValue();
    if (subtype == 'Type0') return _resolveComposite(font, fallback);
    return _resolveSimple(font, fallback);
  }

  static Future<PdfGlyphSource> _resolveSimple(
    CraftPdfDictionary font,
    PdfFontFallback? fallback,
  ) async {
    final widths = <int, double>{};
    final first =
        (await font.numberEntry(CraftPdfName('FirstChar')))?.intValue() ?? 0;
    final array = await font.arrayEntry(CraftPdfName('Widths'));
    if (array != null) {
      for (var i = 0; i < array.size(); i++) {
        final value = await array.get(i);
        if (value is CraftPdfNumber) widths[first + i] = value.doubleValue();
      }
    }

    final descriptor =
        await font.dictionaryEntry(CraftPdfName('FontDescriptor'));
    final missing =
        (await descriptor?.numberEntry(CraftPdfName('MissingWidth')))
                ?.doubleValue() ??
            0;

    final baseFont =
        (await font.nameEntry(CraftPdfName.baseFont))?.getValue() ?? '';
    final codeToUnicode = await _simpleEncoding(font, descriptor);

    // Uma das catorze fontes padrão pode legitimamente omitir `/Widths`: o
    // leitor tem de conhecer as métricas. Sem isto todo avanço vira zero e a
    // linha inteira se empilha no mesmo ponto — o texto some mesmo quando os
    // contornos estão disponíveis.
    if (widths.isEmpty) {
      _fillStandardWidths(widths, baseFont, codeToUnicode);
    }

    final program = await _embeddedProgram(descriptor);

    final resolved = await _applyFallback(program, fallback, baseFont,
        descriptor: descriptor, composite: false);

    return PdfGlyphSource._(
      face: resolved.face,
      failure: resolved.failure,
      composite: false,
      widths: widths,
      defaultWidth: missing,
      codeToUnicode: codeToUnicode,
      cidToGid: null,
    );
  }

  static Future<PdfGlyphSource> _resolveComposite(
      CraftPdfDictionary font, PdfFontFallback? fallback) async {
    // Only the Identity CMaps are decoded here. Anything else would need the
    // full CMap machinery, and guessing would place glyphs at wrong codes —
    // worse than reporting the font as unsupported.
    final encoding =
        (await font.nameEntry(CraftPdfName('Encoding')))?.getValue();
    if (encoding != 'Identity-H' && encoding != 'Identity-V') {
      return PdfGlyphSource._(
        face: null,
        failure: PdfGlyphFailure.unsupportedCMap,
        composite: true,
        widths: const {},
        defaultWidth: 1000,
        codeToUnicode: const {},
        cidToGid: null,
      );
    }

    final descendants = await font.arrayEntry(CraftPdfName('DescendantFonts'));
    final descendant = descendants == null || descendants.isEmptyArray
        ? null
        : await descendants.dictionaryEntry(0);
    if (descendant == null) {
      return PdfGlyphSource._(
        face: null,
        failure: PdfGlyphFailure.unreadableProgram,
        composite: true,
        widths: const {},
        defaultWidth: 1000,
        codeToUnicode: const {},
        cidToGid: null,
      );
    }

    final defaultWidth =
        (await descendant.numberEntry(CraftPdfName('DW')))?.doubleValue() ??
            1000;
    final widths = await _cidWidths(descendant);

    final descriptor =
        await descendant.dictionaryEntry(CraftPdfName('FontDescriptor'));
    final program = await _embeddedProgram(descriptor);
    final cidToGid = await _cidToGidMap(descendant);

    final baseFont =
        (await font.nameEntry(CraftPdfName.baseFont))?.getValue() ?? '';
    final resolved = await _applyFallback(program, fallback, baseFont,
        descriptor: descriptor, composite: true);

    return PdfGlyphSource._(
      face: resolved.face,
      failure: resolved.failure,
      composite: true,
      widths: widths,
      defaultWidth: defaultWidth,
      codeToUnicode: const {},
      cidToGid: cidToGid,
    );
  }

  /// Reads the `/W` array, whose two forms are `c [w w w]` and `cFirst cLast w`.
  static Future<Map<int, double>> _cidWidths(
      CraftPdfDictionary descendant) async {
    final widths = <int, double>{};
    final w = await descendant.arrayEntry(CraftPdfName('W'));
    if (w == null) return widths;

    var i = 0;
    while (i < w.size()) {
      final start = await w.get(i);
      if (start is! CraftPdfNumber) break;
      final next = i + 1 < w.size() ? await w.get(i + 1) : null;

      if (next is CraftPdfArray) {
        final base = start.intValue();
        for (var k = 0; k < next.size(); k++) {
          final value = await next.get(k);
          if (value is CraftPdfNumber) widths[base + k] = value.doubleValue();
        }
        i += 2;
      } else if (next is CraftPdfNumber && i + 2 < w.size()) {
        final value = await w.get(i + 2);
        if (value is! CraftPdfNumber) break;
        final from = start.intValue();
        final to = next.intValue();
        // A hostile file can declare a huge range; cap what is materialised.
        final last = to - from > 65535 ? from + 65535 : to;
        for (var cid = from; cid <= last; cid++) {
          widths[cid] = value.doubleValue();
        }
        i += 3;
      } else {
        break;
      }
    }
    return widths;
  }

  static Future<Uint16List?> _cidToGidMap(CraftPdfDictionary font) async {
    final name = await font.nameEntry(CraftPdfName('CIDToGIDMap'));
    if (name != null) return null; // `/Identity`, or anything else we treat so.

    final stream = await font.streamEntry(CraftPdfName('CIDToGIDMap'));
    if (stream == null) return null;

    final bytes = await stream.getBytes();
    if (bytes == null) return null;
    final map = Uint16List(bytes.length ~/ 2);
    for (var i = 0; i < map.length; i++) {
      map[i] = (bytes[i * 2] << 8) | bytes[i * 2 + 1];
    }
    return map;
  }

  /// Builds the character-code to Unicode table from `/Encoding`.
  static Future<Map<int, int>> _simpleEncoding(
    CraftPdfDictionary font,
    CraftPdfDictionary? descriptor,
  ) async {
    final flags =
        (await descriptor?.numberEntry(CraftPdfName('Flags')))?.intValue() ?? 0;
    final symbolic = (flags & 4) != 0 && (flags & 32) == 0;

    var base = symbolic ? null : 'StandardEncoding';
    Map<int, String>? differences;

    final name = await font.nameEntry(CraftPdfName('Encoding'));
    if (name != null) {
      base = name.getValue();
    } else {
      final dictionary = await font.dictionaryEntry(CraftPdfName('Encoding'));
      if (dictionary != null) {
        base = (await dictionary.nameEntry(CraftPdfName('BaseEncoding')))
                ?.getValue() ??
            base;
        differences = await _differences(
            dictionary.arrayEntry(CraftPdfName('Differences')));
      }
    }

    final table = <int, int>{};
    if (base != null) {
      for (var code = 0; code < 256; code++) {
        try {
          final text =
              PdfSimpleEncoding.decode(base, Uint8List.fromList([code]));
          if (text.isNotEmpty) table[code] = text.runes.first;
        } on FormatException {
          // Undefined slot in this encoding.
        } on ArgumentError {
          // Unknown encoding name; leave the table empty and fall back to the
          // font's own cmap lookups.
          break;
        }
      }
    }

    if (differences != null) {
      for (final entry in differences.entries) {
        final scalar = CraftAdobeGlyphList.nameToUnicode(entry.value);
        if (scalar >= 0) table[entry.key] = scalar;
      }
    }
    return table;
  }

  /// `/Differences` is a flat array where a number resets the running code and
  /// each following name assigns the next one.
  static Future<Map<int, String>?> _differences(
      Future<CraftPdfArray?> pending) async {
    final array = await pending;
    if (array == null) return null;

    final out = <int, String>{};
    var code = 0;
    for (var i = 0; i < array.size(); i++) {
      final item = await array.get(i);
      if (item is CraftPdfNumber) {
        code = item.intValue();
      } else if (item is CraftPdfName) {
        out[code++] = item.getValue();
      }
    }
    return out;
  }

  /// Preenche [widths] com as métricas AFM de uma das catorze fontes padrão.
  ///
  /// As larguras vão em espaço de glifo (1/1000), como o `/Widths` do PDF.
  static void _fillStandardWidths(
    Map<int, double> widths,
    String baseFont,
    Map<int, int> codeToUnicode,
  ) {
    final face = _standardFaceFor(baseFont);
    if (face == null) return;

    // `Symbol` e `ZapfDingbats` trazem a própria codificação embutida; as
    // demais são consultadas pela codificação padrão do PDF.
    const encoding = 'StandardEncoding';
    for (var code = 0; code < 256; code++) {
      try {
        widths[code] = PdfStandardFontMetrics.width(face, encoding, code);
      } on UnsupportedError {
        // Código que esta face não define.
      } on RangeError {
        // Idem.
      }
    }
  }

  /// Mapeia um `/BaseFont` para a face padrão correspondente, se houver.
  static String? _standardFaceFor(String baseFont) {
    final name = baseFont.length > 7 && baseFont[6] == '+'
        ? baseFont.substring(7)
        : baseFont;
    if (PdfStandardFontMetrics.supports(name)) return name;

    // Os apelidos que produtores usam no lugar dos nomes canônicos.
    const aliases = <String, String>{
      'Arial': 'Helvetica',
      'Arial-Bold': 'Helvetica-Bold',
      'Arial,Bold': 'Helvetica-Bold',
      'Arial-Italic': 'Helvetica-Oblique',
      'Arial-BoldItalic': 'Helvetica-BoldOblique',
      'ArialMT': 'Helvetica',
      'Arial-BoldMT': 'Helvetica-Bold',
      'TimesNewRoman': 'Times-Roman',
      'TimesNewRomanPSMT': 'Times-Roman',
      'TimesNewRomanPS-BoldMT': 'Times-Bold',
      'TimesNewRomanPS-ItalicMT': 'Times-Italic',
      'CourierNew': 'Courier',
      'CourierNewPSMT': 'Courier',
    };
    final alias = aliases[name];
    if (alias != null && PdfStandardFontMetrics.supports(alias)) return alias;
    return null;
  }

  /// Pede ao chamador uma fonte de substituição quando o PDF não embute uma.
  static Future<({BLFontFace? face, PdfGlyphFailure? failure})> _applyFallback(
    ({BLFontFace? face, PdfGlyphFailure? failure}) program,
    PdfFontFallback? fallback,
    String baseFont, {
    required CraftPdfDictionary? descriptor,
    required bool composite,
  }) async {
    if (program.face != null || fallback == null) return program;
    // Só faz sentido substituir o que simplesmente não veio. Um programa
    // presente mas ilegível é outro problema, e mascará-lo esconderia o defeito.
    if (program.failure != PdfGlyphFailure.notEmbedded) return program;

    final flags =
        (await descriptor?.numberEntry(CraftPdfName('Flags')))?.intValue() ?? 0;
    final Uint8List? bytes;
    try {
      bytes = await fallback(PdfFontRequest(
          baseFont: baseFont, flags: flags, composite: composite));
    } catch (_) {
      // Um `fallback` que lança não pode derrubar a página.
      return program;
    }
    if (bytes == null || bytes.isEmpty) return program;

    try {
      return (face: BLFontFace.parse(bytes), failure: null);
    } catch (_) {
      return (face: null, failure: PdfGlyphFailure.unreadableProgram);
    }
  }

  static Future<({BLFontFace? face, PdfGlyphFailure? failure})>
      _embeddedProgram(CraftPdfDictionary? descriptor) async {
    if (descriptor == null) {
      return (face: null, failure: PdfGlyphFailure.notEmbedded);
    }

    // `/FontFile2` is TrueType and `/FontFile3` is CFF or OpenType; both are
    // sfnt-shaped or bare CFF. `/FontFile` is Type1, which this cannot parse.
    for (final key in const ['FontFile2', 'FontFile3']) {
      final stream = await descriptor.streamEntry(CraftPdfName(key));
      if (stream == null) continue;
      final bytes = await stream.getBytes();
      if (bytes == null || bytes.isEmpty) continue;
      try {
        return (face: BLFontFace.parse(bytes), failure: null);
      } catch (_) {
        return (face: null, failure: PdfGlyphFailure.unreadableProgram);
      }
    }

    final type1 = await descriptor.streamEntry(CraftPdfName('FontFile'));
    if (type1 != null) {
      return (face: null, failure: PdfGlyphFailure.unreadableProgram);
    }
    return (face: null, failure: PdfGlyphFailure.notEmbedded);
  }
}
