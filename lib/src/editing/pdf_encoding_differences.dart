import 'dart:convert';
import 'dart:typed_data';

import '../io/resources/embedded_font_resources.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import 'pdf_simple_encoding.dart';

/// Independent implementation of PDF 1.7 section 5.5.5 and AGL 2.9 section 2:
/// https://github.com/adobe-type-tools/agl-specification
/// Uses the separately licensed embedded Adobe glyph *data*. Unknown names
/// are rejected when used, rather than silently dropping text as AGL permits.
final class PdfEncodingDifferences {
  PdfEncodingDifferences._(this.base, this.names);
  final String? base;
  final Map<int, String> names;

  static Future<PdfEncodingDifferences> parse(CraftPdfDictionary dictionary,
      {String? defaultBase}) async {
    final rawBase = await dictionary.get(CraftPdfName('BaseEncoding'), true);
    if (rawBase != null && rawBase is! CraftPdfName) {
      throw FormatException('BaseEncoding must be a name.');
    }
    final base =
        rawBase == null ? defaultBase : (rawBase as CraftPdfName).getValue();
    if (base != null) PdfSimpleEncoding.decode(base, Uint8List(0));
    final differences = await dictionary.get(CraftPdfName('Differences'), true);
    if (differences != null && differences is! CraftPdfArray) {
      throw FormatException('Differences must be an array.');
    }
    final names = <int, String>{};
    int? code;
    if (differences is CraftPdfArray) {
      for (var i = 0; i < differences.size(); i++) {
        final item = await differences.get(i);
        if (item is CraftPdfNumber) {
          final value = item.doubleValue();
          if (!value.isFinite ||
              value < 0 ||
              value > 255 ||
              value != value.truncateToDouble()) {
            throw FormatException('Differences index must be an integer byte.');
          }
          code = value.toInt();
        } else if (item is CraftPdfName && code != null && code <= 255) {
          names[code] = item.getValue();
          code++;
        } else {
          throw FormatException('Invalid Differences sequence.');
        }
      }
    }
    return PdfEncodingDifferences._(base, Map.unmodifiable(names));
  }

  String decode(Uint8List codes) {
    final output = StringBuffer();
    for (final code in codes) {
      final name = names[code];
      if (name != null) {
        final text = _glyph(name);
        if (text == null) {
          throw UnsupportedError('Cannot resolve glyph /$name for code $code.');
        }
        output.write(text);
      } else if (base != null) {
        output
            .write(PdfSimpleEncoding.decode(base!, Uint8List.fromList([code])));
      } else {
        throw UnsupportedError(
            'Font built-in encoding is required for code $code.');
      }
    }
    return output.toString();
  }

  static final _glyphs = <String, String>{
    for (final line
        in const LineSplitter().convert(EmbeddedFontResources.glyphList))
      if (line.isNotEmpty && !line.startsWith('#'))
        line.split(';').first: String.fromCharCodes(line
            .split(';')[1]
            .trim()
            .split(RegExp(r'\s+'))
            .map((s) => int.parse(s, radix: 16)))
  };

  static String? _glyph(String name) {
    final output = StringBuffer();
    for (final part in name.split('.').first.split('_')) {
      final known = _glyphs[part];
      if (known != null) {
        output.write(known);
        continue;
      }
      final hex = part.startsWith('uni')
          ? part.substring(3)
          : part.startsWith('u')
              ? part.substring(1)
              : '';
      if (hex.isEmpty || !RegExp(r'^[0-9A-F]+$').hasMatch(hex)) return null;
      final values = <int>[];
      if (part.startsWith('uni') && hex.length % 4 == 0) {
        for (var i = 0; i < hex.length; i += 4) {
          values.add(int.parse(hex.substring(i, i + 4), radix: 16));
        }
      } else if (!part.startsWith('uni') &&
          hex.length >= 4 &&
          hex.length <= 6) {
        values.add(int.parse(hex, radix: 16));
      } else {
        return null;
      }
      if (values.any((v) => v > 0x10ffff || (v >= 0xd800 && v <= 0xdfff)))
        return null;
      output.write(String.fromCharCodes(values));
    }
    return output.isEmpty ? null : output.toString();
  }
}
