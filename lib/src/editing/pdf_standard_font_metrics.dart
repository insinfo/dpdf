import 'dart:convert';
import 'dart:typed_data';

import '../io/font/adobe_glyph_list.dart';
import '../io/resources/embedded_font_resources.dart';
import 'pdf_simple_encoding.dart';

/// Advance widths from the bundled, permissively licensed Adobe AFM data.
/// No glyph outline or ink bounding box is inferred from these advances.
///
/// All fourteen standard faces are available, so bold, italic, serif and
/// monospaced text measures correctly without embedding a font program.
abstract final class PdfStandardFontMetrics {
  /// Per-face tables, built on first use of that face.
  ///
  /// `_byCode` is keyed by the AFM's own StandardEncoding code, `_byScalar` by
  /// the Unicode scalar the glyph name maps to. A caller asking for a
  /// WinAnsi byte is answered through the scalar table, because the two
  /// encodings assign different bytes to the same glyph.
  static final Map<String, Map<int, double>> _byCode = {};
  static final Map<String, Map<int, double>> _byScalar = {};

  /// The faces this package can measure: the PDF core 14.
  static Set<String> get availableFonts => EmbeddedFontResources.standardFaces;

  /// True when [font] names a face with bundled metrics.
  static bool supports(String font) => EmbeddedFontResources.hasMetrics(font);

  /// Advance width in 1/1000 text units for a single byte [code].
  ///
  /// [encoding] must be `StandardEncoding` or `WinAnsiEncoding`. Throws
  /// [UnsupportedError] for a face with no bundled metrics, or for a byte the
  /// face does not define.
  static double width(String font, String encoding, int code) {
    if (code < 0 || code > 255) throw RangeError.range(code, 0, 255, 'code');
    if (!EmbeddedFontResources.hasMetrics(font)) {
      throw UnsupportedError('No bundled advance metrics for $font.');
    }
    _load(font);

    final byCode = _byCode[font]!;
    if (encoding == 'StandardEncoding') {
      final value = byCode[code];
      if (value == null) {
        throw UnsupportedError(
            'Missing $font metric for $encoding byte $code.');
      }
      return value;
    }

    // Symbol and ZapfDingbats have their own built-in encoding; their AFM
    // codes are the byte values a document uses, whatever /Encoding says.
    if (font == 'Symbol' || font == 'ZapfDingbats') {
      final value = byCode[code];
      if (value == null) {
        throw UnsupportedError(
            'Missing $font metric for $encoding byte $code.');
      }
      return value;
    }

    final text = PdfSimpleEncoding.decode(encoding, Uint8List.fromList([code]));
    var scalar = text.runes.single;
    // Appendix D WinAnsi aliases select the ordinary space/hyphen glyphs.
    if (scalar == 0xa0) scalar = 0x20;
    if (scalar == 0xad) scalar = 0x2d;
    final value = _byScalar[font]![scalar];
    if (value == null) {
      throw UnsupportedError('Missing $font metric for $encoding byte $code.');
    }
    return value;
  }

  /// Advance width for [code], or [fallback] when the face does not define it.
  ///
  /// Use this when measuring text that may contain characters a face lacks and
  /// an approximate line length is better than an exception.
  static double widthOrDefault(
      String font, String encoding, int code, double fallback) {
    if (code < 0 || code > 255) return fallback;
    try {
      return width(font, encoding, code);
    } on UnsupportedError {
      return fallback;
    } on ArgumentError {
      return fallback;
    }
  }

  /// Total advance of [text] at [fontSize] points, in points.
  ///
  /// A character the encoding or the face cannot represent falls back to the
  /// width of a space. Measuring is a layout decision, so it stays total: a
  /// caller measuring a line must not have a whole page aborted by one
  /// character it could not have drawn anyway.
  static double textWidth(
      String font, String encoding, String text, double fontSize) {
    if (text.isEmpty) return 0;
    final space = widthOrDefault(font, encoding, 32, 500);
    var total = 0.0;
    for (final rune in text.runes) {
      total += _runeWidth(font, encoding, rune, space);
    }
    return total / 1000 * fontSize;
  }

  static double _runeWidth(
      String font, String encoding, int rune, double fallback) {
    final Uint8List encoded;
    try {
      encoded = PdfSimpleEncoding.encode(encoding, String.fromCharCode(rune));
    } on FormatException {
      return fallback;
    } on UnsupportedError {
      return fallback;
    }
    var total = 0.0;
    for (final code in encoded) {
      total += widthOrDefault(font, encoding, code, fallback);
    }
    return total;
  }

  static void _load(String font) {
    if (_byCode.containsKey(font)) return;
    final byCode = <int, double>{};
    final byScalar = <int, double>{};

    for (final line in const LineSplitter()
        .convert(latin1.decode(EmbeddedFontResources.metrics(font)!))) {
      if (!line.startsWith('C ')) continue;
      final fields = <String, String>{};
      for (final field in line.split(';')) {
        final item = field.trim();
        final separator = item.indexOf(' ');
        if (separator > 0) {
          fields[item.substring(0, separator)] = item.substring(separator + 1);
        }
      }
      final code = int.parse(fields['C']!);
      final advance = double.parse(fields['WX']!);
      final name = fields['N']!;
      if (code >= 0) byCode[code] = advance;
      // The local legacy AGL assigns mu to Greek U+03BC; PDF WinAnsi uses
      // the micro sign U+00B5. Bind the AFM glyph directly for this alias.
      final scalar =
          name == 'mu' ? 0xb5 : CraftAdobeGlyphList.nameToUnicode(name);
      if (scalar >= 0) {
        final previous = byScalar[scalar];
        if (previous != null && previous != advance) {
          throw StateError('Ambiguous embedded $font width for $scalar.');
        }
        byScalar[scalar] = advance;
      }
    }

    _byCode[font] = byCode;
    _byScalar[font] = byScalar;
  }
}
