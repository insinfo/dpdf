import 'dart:typed_data';

import 'package:dgfx/dgfx.dart';

import '../editing/pdf_simple_encoding.dart';
import '../editing/pdf_standard_font_metrics.dart';
import '../io/font/cmap/cmap_cid_to_codepoint.dart';
import '../io/font/cmap/cmap_location_from_bytes.dart';
import '../io/font/cmap/cmap_parser.dart';
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

/// Adapta o catálogo compartilhado do dgfx ao fallback do renderizador PDF.
///
/// O nome PostScript de `/BaseFont` costuma terminar em `-Bold`, `-Italic` ou
/// combinações equivalentes. A consulta remove esses sufixos porque peso e
/// inclinação já são dimensões próprias do catálogo.
PdfFontFallback pdfFontFallbackFromCollection(BLFontCollection collection) {
  return (request) async {
    var family = request.familyName;
    family = family.replaceFirst(
      RegExp(r'[-,]?(BoldItalic|BoldOblique|Bold|Italic|Oblique)$',
          caseSensitive: false),
      '',
    );
    final normalized = family.toLowerCase().replaceAll(' ', '');
    final compatible =
        normalized.startsWith('helvetica') || normalized.startsWith('arial')
            ? const <String>[
                'Arial',
                'Liberation Sans',
                'DejaVu Sans',
                'Noto Sans',
              ]
            : normalized.startsWith('times')
                ? const <String>[
                    'Times New Roman',
                    'Liberation Serif',
                    'DejaVu Serif',
                    'Noto Serif',
                  ]
                : normalized.startsWith('courier')
                    ? const <String>[
                        'Courier New',
                        'Liberation Mono',
                        'DejaVu Sans Mono',
                        'Noto Sans Mono',
                      ]
                    : const <String>[];
    final face = await collection.resolve(BLFontQuery(
      <String>[
        family,
        ...compatible,
        if (request.isFixedPitch) 'monospace',
        if (request.isSerif) 'serif' else 'sans-serif',
      ],
      weight: request.isBold ? 700 : 400,
      slant: request.isItalic ? BLFontSlant.italic : BLFontSlant.normal,
    ));
    return face?.data;
  };
}

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

  /// For simple CFF fonts: character code to the glyph name selected by the
  /// PDF Encoding and Differences dictionary.
  final Map<int, String> _codeToGlyphName;

  /// Whether unmapped simple-font codes use the CFF program's own Encoding.
  final bool _useCffEncoding;

  /// For composite fonts: CID to glyph index, when `/CIDToGIDMap` is a stream.
  /// Null means the identity mapping.
  final Uint16List? _cidToGid;

  /// CMap embutida que traduz bytes em CIDs, quando `/Encoding` é um stream.
  /// Null significa Identity, onde o código de dois bytes já é o CID.
  final _EmbeddedCMap? _cmap;

  /// True quando o programa embutido não traz `cmap` utilizável.
  ///
  /// Um subconjunto de fonte embutido frequentemente omite a tabela `cmap`,
  /// porque o produtor já sabe qual glifo cada código designa. A ISO 32000-1
  /// §9.6.6.4 diz que nesse caso o código de caractere É o índice do glifo.
  final bool _codeIsGlyphIndex;

  final Map<int, int?> _glyphCache = <int, int?>{};

  PdfGlyphSource._({
    required this.face,
    required this.failure,
    required this.composite,
    required Map<int, double> widths,
    required double defaultWidth,
    required Map<int, int> codeToUnicode,
    required Map<int, String> codeToGlyphName,
    required Uint16List? cidToGid,
    _EmbeddedCMap? cmap,
    bool codeIsGlyphIndex = false,
    bool useCffEncoding = false,
  })  : _cmap = cmap,
        _codeIsGlyphIndex = codeIsGlyphIndex,
        _useCffEncoding = useCffEncoding,
        _widths = widths,
        _defaultWidth = defaultWidth,
        _codeToUnicode = codeToUnicode,
        _codeToGlyphName = codeToGlyphName,
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
    final cmap = _cmap;
    if (cmap != null) return cmap.split(bytes);

    final out = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      out.add((bytes[i] << 8) | bytes[i + 1]);
    }
    // An odd trailing byte is malformed; keeping it as a code is closer to
    // what viewers do than dropping the glyph silently.
    if (bytes.length.isOdd) out.add(bytes.last);
    return out;
  }

  /// CID para [code], que é o próprio código sob uma CMap Identity.
  int _cidFor(int code) => _cmap?.cid(code) ?? code;

  /// Advance for [code], in text space units (already divided by 1000).
  ///
  /// `/W` de uma fonte composta é indexado por CID, não pelo código, então a
  /// CMap tem de ser aplicada antes da consulta.
  double width(int code) {
    final key = composite ? _cidFor(code) : code;
    return (_widths[key] ?? _defaultWidth) / 1000.0;
  }

  /// Glyph index for [code], or null when the program has no glyph for it.
  int? glyph(int code) {
    if (face == null) return null;
    return _glyphCache.putIfAbsent(code, () => _resolveGlyph(code));
  }

  int? _resolveGlyph(int code) {
    final font = face!;
    if (composite) {
      // A CMap traduz o código em CID; sob Identity os dois coincidem.
      // `/CIDToGIDMap` então diz qual glifo do programa é aquele CID.
      final cid = _cidFor(code);
      final map = _cidToGid;
      if (map == null) {
        // CIDFontType0/CFF não usa o `/CIDToGIDMap` de CIDFontType2. Nesse
        // caso o charset interno do CFF é que relaciona cada CID ao GID da
        // CharStrings INDEX; assumir identidade funciona apenas por acaso em
        // fontes não subsetadas.
        final cff = font.cffInfo;
        if (cff != null && cff.isCID) return cff.cidToGlyphId[cid] ?? 0;
        return cid;
      }
      return cid < map.length ? map[cid] : 0;
    }

    final cff = font.cffInfo;
    if (cff != null && !cff.isCID) {
      final glyphName = _codeToGlyphName[code];
      final byName = glyphName == null ? null : font.glyphIdForName(glyphName);
      if (byName != null && byName != 0) return byName;
      if (_useCffEncoding) {
        final encoded = cff.codeToGlyphId[code];
        if (encoded != null && encoded != 0) return encoded;
      }
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
    if (direct != 0) return direct;

    // Sem `cmap` utilizável o código é o próprio índice do glifo. Só vale
    // quando a fonte de fato não mapeia nada: aplicar isso a uma fonte com
    // `cmap` funcional desenharia glifos errados em vez de nenhum, que é pior.
    if (_codeIsGlyphIndex && code > 0 && code < font.glyphCount) return code;
    return null;
  }

  /// Resolves the `/Font` entry named [name] in [resources].
  static Future<PdfGlyphSource?> resolve(
    PdfDictionary? resources,
    String name, {
    PdfFontFallback? fallback,
  }) async {
    final fonts = await resources?.dictionaryEntry(PdfName('Font'));
    final font = await fonts?.dictionaryEntry(PdfName(name));
    if (font == null) return null;

    final subtype = (await font.nameEntry(PdfName.subtype))?.getValue();
    if (subtype == 'Type0') return _resolveComposite(font, fallback);
    return _resolveSimple(font, fallback);
  }

  static Future<PdfGlyphSource> _resolveSimple(
    PdfDictionary font,
    PdfFontFallback? fallback,
  ) async {
    final widths = <int, double>{};
    final first =
        (await font.numberEntry(PdfName('FirstChar')))?.intValue() ?? 0;
    final array = await font.arrayEntry(PdfName('Widths'));
    if (array != null) {
      for (var i = 0; i < array.size(); i++) {
        final value = await array.get(i);
        if (value is PdfNumber) widths[first + i] = value.doubleValue();
      }
    }

    final descriptor = await font.dictionaryEntry(PdfName('FontDescriptor'));
    final missing = (await descriptor?.numberEntry(PdfName('MissingWidth')))
            ?.doubleValue() ??
        0;

    final baseFont = (await font.nameEntry(PdfName.baseFont))?.getValue() ?? '';
    final encoding = await _simpleEncoding(font, descriptor);
    final codeToUnicode = encoding.unicode;

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
      codeToGlyphName: encoding.glyphNames,
      cidToGid: null,
      codeIsGlyphIndex: _lacksUsableCmap(resolved.face),
      useCffEncoding: encoding.usesFontEncoding,
    );
  }

  static Future<PdfGlyphSource> _resolveComposite(
      PdfDictionary font, PdfFontFallback? fallback) async {
    // `/Encoding` diz como os bytes da cadeia viram CIDs. As Identity são a
    // identidade em dois bytes; um stream é um programa CMap que traz os
    // próprios intervalos, e é parseado. Uma CMap predefinida que não seja
    // Identity — as CJK — exige tabelas que este pacote não embute, e é
    // recusada em vez de adivinhada: posicionar glifos em códigos errados
    // seria pior do que relatar a fonte como não suportada.
    final encoding = (await font.nameEntry(PdfName('Encoding')))?.getValue();
    _EmbeddedCMap? embedded;
    if (encoding == null) {
      final stream = await font.streamEntry(PdfName('Encoding'));
      final bytes = await stream?.getBytes();
      if (bytes != null && bytes.isNotEmpty) {
        embedded = _EmbeddedCMap.parse(bytes);
      }
    }
    if (embedded == null &&
        encoding != 'Identity-H' &&
        encoding != 'Identity-V') {
      return PdfGlyphSource._(
        face: null,
        failure: PdfGlyphFailure.unsupportedCMap,
        composite: true,
        widths: const {},
        defaultWidth: 1000,
        codeToUnicode: const {},
        codeToGlyphName: const {},
        cidToGid: null,
      );
    }

    final descendants = await font.arrayEntry(PdfName('DescendantFonts'));
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
        codeToGlyphName: const {},
        cidToGid: null,
      );
    }

    final defaultWidth =
        (await descendant.numberEntry(PdfName('DW')))?.doubleValue() ?? 1000;
    final widths = await _cidWidths(descendant);

    final descriptor =
        await descendant.dictionaryEntry(PdfName('FontDescriptor'));
    final program = await _embeddedProgram(descriptor);
    final cidToGid = await _cidToGidMap(descendant);

    final baseFont = (await font.nameEntry(PdfName.baseFont))?.getValue() ?? '';
    final resolved = await _applyFallback(program, fallback, baseFont,
        descriptor: descriptor, composite: true);

    return PdfGlyphSource._(
      face: resolved.face,
      failure: resolved.failure,
      composite: true,
      widths: widths,
      defaultWidth: defaultWidth,
      codeToUnicode: const {},
      codeToGlyphName: const {},
      cidToGid: cidToGid,
      cmap: embedded,
    );
  }

  /// Reads the `/W` array, whose two forms are `c [w w w]` and `cFirst cLast w`.
  static Future<Map<int, double>> _cidWidths(PdfDictionary descendant) async {
    final widths = <int, double>{};
    final w = await descendant.arrayEntry(PdfName('W'));
    if (w == null) return widths;

    var i = 0;
    while (i < w.size()) {
      final start = await w.get(i);
      if (start is! PdfNumber) break;
      final next = i + 1 < w.size() ? await w.get(i + 1) : null;

      if (next is PdfArray) {
        final base = start.intValue();
        for (var k = 0; k < next.size(); k++) {
          final value = await next.get(k);
          if (value is PdfNumber) widths[base + k] = value.doubleValue();
        }
        i += 2;
      } else if (next is PdfNumber && i + 2 < w.size()) {
        final value = await w.get(i + 2);
        if (value is! PdfNumber) break;
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

  static Future<Uint16List?> _cidToGidMap(PdfDictionary font) async {
    final name = await font.nameEntry(PdfName('CIDToGIDMap'));
    if (name != null) return null; // `/Identity`, or anything else we treat so.

    final stream = await font.streamEntry(PdfName('CIDToGIDMap'));
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
  static Future<
      ({
        Map<int, int> unicode,
        Map<int, String> glyphNames,
        bool usesFontEncoding
      })> _simpleEncoding(
    PdfDictionary font,
    PdfDictionary? descriptor,
  ) async {
    final flags =
        (await descriptor?.numberEntry(PdfName('Flags')))?.intValue() ?? 0;
    final symbolic = (flags & 4) != 0 && (flags & 32) == 0;

    var base = symbolic ? null : 'StandardEncoding';
    Map<int, String>? differences;

    final name = await font.nameEntry(PdfName('Encoding'));
    if (name != null) {
      base = name.getValue();
    } else {
      final dictionary = await font.dictionaryEntry(PdfName('Encoding'));
      if (dictionary != null) {
        base =
            (await dictionary.nameEntry(PdfName('BaseEncoding')))?.getValue() ??
                base;
        differences =
            await _differences(dictionary.arrayEntry(PdfName('Differences')));
      }
    }

    final table = <int, int>{};
    final glyphNames = <int, String>{};
    if (base != null) {
      for (var code = 0; code < 256; code++) {
        try {
          final text =
              PdfSimpleEncoding.decode(base, Uint8List.fromList([code]));
          if (text.isNotEmpty) {
            final scalar = text.runes.first;
            table[code] = scalar;
            final name = AdobeGlyphList.unicodeToName(scalar);
            if (name != null) glyphNames[code] = name;
          }
        } on FormatException {
          // Undefined slot in this encoding.
        } on UnsupportedError {
          // Uma codificação que este pacote não tabela — MacExpertEncoding, ou
          // um nome fora do padrão. Deixar a tabela vazia faz a resolução cair
          // no cmap da própria fonte, que é melhor do que descartar a fonte
          // inteira: antes esta exceção subia e todo o texto do documento
          // deixava de ser desenhado.
          break;
        } on ArgumentError {
          break;
        }
      }
    }

    if (differences != null) {
      for (final entry in differences.entries) {
        final scalar = AdobeGlyphList.nameToUnicode(entry.value);
        if (scalar >= 0) table[entry.key] = scalar;
        glyphNames[entry.key] = entry.value;
      }
    }
    return (
      unicode: table,
      glyphNames: glyphNames,
      usesFontEncoding: base == null,
    );
  }

  /// `/Differences` is a flat array where a number resets the running code and
  /// each following name assigns the next one.
  static Future<Map<int, String>?> _differences(
      Future<PdfArray?> pending) async {
    final array = await pending;
    if (array == null) return null;

    final out = <int, String>{};
    var code = 0;
    for (var i = 0; i < array.size(); i++) {
      final item = await array.get(i);
      if (item is PdfNumber) {
        code = item.intValue();
      } else if (item is PdfName) {
        out[code++] = item.getValue();
      }
    }
    return out;
  }

  /// True quando [face] não mapeia ponto de código nenhum.
  ///
  /// Sonda a faixa que qualquer texto latino usa. Uma fonte com `cmap` real
  /// responde a pelo menos um destes; um subconjunto sem a tabela responde a
  /// nenhum, e aí o código de caractere é o índice do glifo.
  static bool _lacksUsableCmap(BLFontFace? face) {
    if (face == null) return false;
    for (var code = 0x20; code <= 0x7E; code++) {
      if (face.mapCodePoint(code) != 0) return false;
      if (face.mapCodePoint(0xF000 + code) != 0) return false;
    }
    return true;
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
    required PdfDictionary? descriptor,
    required bool composite,
  }) async {
    if (program.face != null || fallback == null) return program;
    // Só faz sentido substituir o que simplesmente não veio. Um programa
    // presente mas ilegível é outro problema, e mascará-lo esconderia o defeito.
    if (program.failure != PdfGlyphFailure.notEmbedded) return program;

    final flags =
        (await descriptor?.numberEntry(PdfName('Flags')))?.intValue() ?? 0;
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
      _embeddedProgram(PdfDictionary? descriptor) async {
    if (descriptor == null) {
      return (face: null, failure: PdfGlyphFailure.notEmbedded);
    }

    // `/FontFile2` is TrueType and `/FontFile3` is CFF or OpenType; both are
    // sfnt-shaped or bare CFF. `/FontFile` is Type1, which this cannot parse.
    for (final key in const ['FontFile2', 'FontFile3']) {
      final stream = await descriptor.streamEntry(PdfName(key));
      if (stream == null) continue;
      final bytes = await stream.getBytes();
      if (bytes == null || bytes.isEmpty) continue;
      try {
        return (face: BLFontFace.parse(bytes), failure: null);
      } catch (_) {
        return (face: null, failure: PdfGlyphFailure.unreadableProgram);
      }
    }

    final type1 = await descriptor.streamEntry(PdfName('FontFile'));
    if (type1 != null) {
      return (face: null, failure: PdfGlyphFailure.unreadableProgram);
    }
    return (face: null, failure: PdfGlyphFailure.notEmbedded);
  }
}

/// A CMap carried inside the PDF, as `/Encoding` of a Type0 font.
///
/// It is a PostScript-like program declaring which byte sequences are valid
/// codes (`codespacerange`) and how those codes map to CIDs (`cidrange` and
/// `cidchar`). Unlike Identity, the codes are not necessarily two bytes: a
/// single CMap can mix one and two byte codes, and splitting the string wrong
/// shifts every glyph after the mistake.
class _EmbeddedCMap {
  /// Comprimentos de código válidos, do menor para o maior, com os intervalos
  /// de cada um como pares `(baixo, alto)` já convertidos para inteiros.
  final Map<int, List<(int, int)>> _spans;

  /// Código para CID.
  final Map<int, int> _toCid;

  const _EmbeddedCMap._(this._spans, this._toCid);

  /// Parseia [bytes], ou devolve null se o programa não for legível.
  static _EmbeddedCMap? parse(Uint8List bytes) {
    final collector = CMapCidToCodepoint();
    try {
      CMapParser.loadCidMappingsSync(
          'embedded', collector, CMapLocationFromBytes(bytes));
    } catch (_) {
      // Um programa malformado não pode derrubar a página; a fonte volta a
      // ser relatada como não suportada.
      return null;
    }

    final spans = <int, List<(int, int)>>{};
    final ranges = collector.getCodeSpaceRanges();
    for (var i = 0; i + 1 < ranges.length; i += 2) {
      final low = ranges[i];
      final high = ranges[i + 1];
      if (low.isEmpty || low.length != high.length) continue;
      (spans[low.length] ??= []).add((_toInt(low), _toInt(high)));
    }

    final toCid = <int, int>{};
    collector.map.forEach((cid, code) {
      if (code.isNotEmpty) toCid[_toInt(code)] = cid;
    });

    if (spans.isEmpty && toCid.isEmpty) return null;
    // Sem `codespacerange` declarado, dois bytes é o que praticamente todo
    // Type0 usa, e é o que a Identity faz.
    if (spans.isEmpty) spans[2] = [(0, 0xFFFF)];
    return _EmbeddedCMap._(spans, toCid);
  }

  static int _toInt(List<int> bytes) {
    var value = 0;
    for (final b in bytes) {
      value = (value << 8) | (b & 0xFF);
    }
    return value;
  }

  int cid(int code) => _toCid[code] ?? code;

  /// Quebra [bytes] em códigos, respeitando os comprimentos declarados.
  List<int> split(Uint8List bytes) {
    final lengths = _spans.keys.toList()..sort();
    final out = <int>[];
    var i = 0;
    while (i < bytes.length) {
      var taken = 0;
      for (final length in lengths) {
        if (i + length > bytes.length) continue;
        var value = 0;
        for (var k = 0; k < length; k++) {
          value = (value << 8) | bytes[i + k];
        }
        final within =
            _spans[length]!.any((span) => value >= span.$1 && value <= span.$2);
        if (within) {
          out.add(value);
          taken = length;
          break;
        }
      }
      if (taken == 0) {
        // Byte que nenhum intervalo aceita. Consumir o menor comprimento
        // declarado mantém o resto da cadeia alinhado, que é o que os leitores
        // fazem; parar aqui perderia todo o texto seguinte.
        final fallback = lengths.first;
        var value = 0;
        for (var k = 0; k < fallback && i + k < bytes.length; k++) {
          value = (value << 8) | bytes[i + k];
        }
        out.add(value);
        taken = fallback;
      }
      i += taken;
    }
    return out;
  }
}
