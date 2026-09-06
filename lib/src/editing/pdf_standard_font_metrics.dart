import 'dart:convert';
import 'dart:typed_data';

import '../io/font/adobe_glyph_list.dart';
import '../io/resources/embedded_font_resources.dart';
import 'pdf_simple_encoding.dart';

/// Advance widths from the bundled, permissively licensed Adobe AFM data.
/// No glyph outline or ink bounding box is inferred from these advances.
abstract final class PdfStandardFontMetrics {
  static final _standard = <int, double>{};
  static final _unicode = <int, double>{};
  static bool _loaded = false;

  static double width(String font, String encoding, int code) {
    if (code < 0 || code > 255) throw RangeError.range(code, 0, 255, 'code');
    final text = PdfSimpleEncoding.decode(encoding, Uint8List.fromList([code]));
    if (font == 'Courier') return 600;
    if (font != 'Helvetica') {
      throw UnsupportedError('No bundled advance metrics for $font.');
    }
    _load();
    var scalar = text.runes.single;
    // Appendix D WinAnsi aliases select the ordinary space/hyphen glyphs.
    if (scalar == 0xa0) scalar = 0x20;
    if (scalar == 0xad) scalar = 0x2d;
    final value =
        encoding == 'StandardEncoding' ? _standard[code] : _unicode[scalar];
    if (value == null) {
      throw UnsupportedError('Missing $font metric for $encoding byte $code.');
    }
    return value;
  }

  static void _load() {
    if (_loaded) return;
    for (final line in const LineSplitter()
        .convert(latin1.decode(EmbeddedFontResources.metrics('Helvetica')!))) {
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
      if (code >= 0) _standard[code] = advance;
      // The local legacy AGL assigns mu to Greek U+03BC; PDF WinAnsi uses
      // the micro sign U+00B5. Bind the AFM glyph directly for this alias.
      final scalar =
          name == 'mu' ? 0xb5 : CraftAdobeGlyphList.nameToUnicode(name);
      if (scalar >= 0) {
        final previous = _unicode[scalar];
        if (previous != null && previous != advance) {
          throw StateError('Ambiguous embedded Helvetica width for $scalar.');
        }
        _unicode[scalar] = advance;
      }
    }
    _loaded = true;
  }
}
