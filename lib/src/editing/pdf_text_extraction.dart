import 'dart:convert';
import '../platform/compression.dart';
import 'dart:typed_data';

import 'pdf_unicode_cmap.dart';
import '../io/font/pdf_encodings.dart';
import 'pdf_simple_encoding.dart';
import 'pdf_standard_font_metrics.dart';
import 'pdf_encoding_differences.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_page.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/pdf_writer.dart';

part 'pdf_text_positions.dart';
part 'pdf_text_redaction.dart';
part 'pdf_graphics_envelope.dart';

/// Decodes PDF character codes for a selected font resource.
/// A decoder must apply that font's Encoding/ToUnicode mapping.
typedef PdfCharacterDecoder = String Function(String font, Uint8List codes);

/// Extracts text in content-stream order, not visual reading order.
///
/// Form XObjects are visited in painting order. Marked-content replacement
/// text is emitted once per sequence; inline images remain unsupported.
class PdfTextExtraction {
  static Future<String> fromPage(CraftPdfPage page,
      {PdfCharacterDecoder? decoder}) async {
    var resources =
        await page.pdfRepresentation().dictionaryEntry(CraftPdfName.resources);
    CraftPdfDictionary? parent = page.pdfRepresentation();
    final visited = <CraftPdfDictionary>{};
    while (resources == null && parent != null && visited.add(parent)) {
      parent = await parent.dictionaryEntry(CraftPdfName.parent);
      resources = await parent?.dictionaryEntry(CraftPdfName.resources);
    }
    return _fromResources(await _strictContent(page), resources, decoder,
        <CraftPdfStream>{}, null);
  }

  static Future<String> _fromResources(
      Uint8List bytes,
      CraftPdfDictionary? resources,
      PdfCharacterDecoder? customDecoder,
      Set<CraftPdfStream> activeForms,
      _FontBinding? inheritedFont,
      {bool suppressed = false}) async {
    final decoder = customDecoder ?? await _resourceDecoder(resources);
    final propertyValues = <String, Object>{};
    final properties =
        await resources?.dictionaryEntry(CraftPdfName('Properties'));
    if (properties != null) {
      for (final entry in await properties.entrySet()) {
        final property = await properties.get(entry.key, true);
        if (property is CraftPdfDictionary) {
          final replacement =
              await property.get(CraftPdfName('ActualText'), true);
          propertyValues[entry.key.getValue()] = replacement == null
              ? <String, Object>{}
              : <String, Object>{'ActualText': replacement};
        } else {
          propertyValues[entry.key.getValue()] = false;
        }
      }
    }
    final parts = _contentParts(bytes,
        decoder: decoder,
        inheritedFont: inheritedFont,
        allowForms: true,
        properties: propertyValues,
        suppressed: suppressed);
    final output = StringBuffer();
    for (final part in parts) {
      if (part is String) {
        output.write(part);
        continue;
      }
      final invocation = part as _FormInvocation;
      final objects = await resources?.dictionaryEntry(CraftPdfName('XObject'));
      final object = await objects?.get(CraftPdfName(invocation.name), true);
      if (object is! CraftPdfStream) {
        throw FormatException('Missing XObject stream /${invocation.name}.');
      }
      final subtype =
          (await object.nameEntry(CraftPdfName.subtype))?.getValue();
      if (subtype == 'Image') continue;
      if (subtype != 'Form') {
        throw UnsupportedError('Unsupported XObject subtype: $subtype.');
      }
      if (activeForms.length >= 128 || !activeForms.add(object)) {
        throw FormatException(
            'Recursive or excessively nested Form XObject /${invocation.name}.');
      }
      try {
        final local = await object.get(CraftPdfName.resources, true);
        if (local != null && local is! CraftPdfDictionary) {
          throw FormatException('Form resources must be a dictionary.');
        }
        output.write(await _fromResources(
            await _strictStream(object),
            local as CraftPdfDictionary? ?? resources,
            customDecoder,
            activeForms,
            invocation.font,
            suppressed: invocation.suppressed));
      } finally {
        activeForms.remove(object);
      }
    }
    return output.toString();
  }

  static String _replacementText(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      if (bytes.length.isOdd)
        throw FormatException('ActualText has incomplete UTF-16 data.');
      final units = <int>[];
      for (var i = 2; i < bytes.length; i += 2) {
        final unit = (bytes[i] << 8) | bytes[i + 1];
        if (unit >= 0xdc00 &&
            unit <= 0xdfff &&
            (units.isEmpty || units.last < 0xd800 || units.last > 0xdbff)) {
          throw FormatException(
              'ActualText has an unmatched UTF-16 surrogate.');
        }
        if (units.isNotEmpty &&
            units.last >= 0xd800 &&
            units.last <= 0xdbff &&
            (unit < 0xdc00 || unit > 0xdfff)) {
          throw FormatException(
              'ActualText has an unmatched UTF-16 surrogate.');
        }
        units.add(unit);
      }
      if (units.isNotEmpty && units.last >= 0xd800 && units.last <= 0xdbff) {
        throw FormatException('ActualText has an unmatched UTF-16 surrogate.');
      }
      return String.fromCharCodes(units);
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf) {
      return utf8.decode(bytes.sublist(3));
    }
    return CraftPdfEncodings.convertToString(bytes, 'PDF');
  }

  static Future<PdfCharacterDecoder> _resourceDecoder(
      CraftPdfDictionary? resources) async {
    final fonts = await resources?.dictionaryEntry(CraftPdfName.font);
    final permitted = <String, String>{};
    final unicodeMaps = <String, PdfUnicodeCMap>{};
    final differences = <String, PdfEncodingDifferences>{};
    if (fonts != null) {
      for (final entry in await fonts.entrySet()) {
        final font = await fonts.dictionaryEntry(entry.key);
        final unicode = await font?.get(CraftPdfName('ToUnicode'), true);
        if (unicode != null) {
          if (unicode is! CraftPdfStream) {
            throw FormatException('ToUnicode must be a stream.');
          }
          if (unicode.containsKey(CraftPdfName('UseCMap'))) {
            throw UnsupportedError(
                'Inherited ToUnicode CMaps are unsupported.');
          }
          unicodeMaps[entry.key.getValue()] =
              PdfUnicodeCMap.parse(await _strictStream(unicode));
          continue;
        }
        final base = (await font?.nameEntry(CraftPdfName.baseFont))?.getValue();
        final subtype =
            (await font?.nameEntry(CraftPdfName.subtype))?.getValue();
        final encoding =
            (await font?.nameEntry(CraftPdfName.encoding))?.getValue();
        final latinBase14 = subtype == 'Type1' &&
            const {
              'Helvetica',
              'Helvetica-Bold',
              'Helvetica-Oblique',
              'Helvetica-BoldOblique',
              'Courier',
              'Courier-Bold',
              'Courier-Oblique',
              'Courier-BoldOblique',
              'Times-Roman',
              'Times-Bold',
              'Times-Italic',
              'Times-BoldItalic'
            }.contains(base);
        final encodingObject = await font?.get(CraftPdfName.encoding, true);
        if (encodingObject is CraftPdfDictionary &&
            (subtype == 'Type1' ||
                subtype == 'TrueType' ||
                subtype == 'Type3')) {
          differences[entry.key.getValue()] =
              await PdfEncodingDifferences.parse(encodingObject,
                  defaultBase: latinBase14 ? 'StandardEncoding' : null);
          continue;
        }
        if (latinBase14 &&
            (await font!.get(CraftPdfName.encoding) == null ||
                encoding == 'WinAnsiEncoding' ||
                encoding == 'StandardEncoding') &&
            !font.containsKey(CraftPdfName('ToUnicode'))) {
          permitted[entry.key.getValue()] = encoding ?? 'StandardEncoding';
        }
      }
    }
    return (font, codes) {
      final unicode = unicodeMaps[font];
      if (unicode != null) return unicode.decode(codes);
      final custom = differences[font];
      if (custom != null) return custom.decode(codes);
      if (!permitted.containsKey(font)) {
        throw UnsupportedError('A character decoder is required for /$font.');
      }
      return PdfSimpleEncoding.decode(permitted[font]!, codes);
    };
  }

  static Future<Uint8List> _strictContent(CraftPdfPage page) async {
    final result = BytesBuilder();
    final contents =
        await page.pdfRepresentation().get(CraftPdfName.contents, true);
    if (contents != null &&
        contents is! CraftPdfStream &&
        contents is! CraftPdfArray) {
      throw FormatException('Page contents must be a stream or array.');
    }
    final count = await page.contentSegmentCount();
    for (var i = 0; i < count; i++) {
      final object = await page.contentSegmentAt(i);
      if (object is! CraftPdfStream) {
        throw FormatException('Page contents must resolve to streams.');
      }
      final bytes = await _strictStream(object);
      result.add(bytes);
      result.addByte(10);
    }
    return result.takeBytes();
  }

  static Future<Uint8List> _strictStream(CraftPdfStream object) async {
    if (object.containsKey(CraftPdfName('DecodeParms'))) {
      throw UnsupportedError(
          'Content-stream decode parameters require a dedicated decoder.');
    }
    var bytes = await object.getBytes(false);
    if (bytes == null) throw FormatException('Missing stream bytes.');
    final filter = await object.get(CraftPdfName.filter, true);
    final names = <String>[];
    if (filter is CraftPdfName) {
      names.add(filter.getValue());
    } else if (filter is CraftPdfArray) {
      for (var j = 0; j < filter.size(); j++) {
        final name = await filter.get(j);
        if (name is! CraftPdfName)
          throw FormatException('Invalid stream filter.');
        names.add(name.getValue());
      }
    } else if (filter != null) {
      throw FormatException('Invalid stream filter.');
    }
    for (final name in names) {
      if (name != 'FlateDecode' && name != 'Fl') {
        throw UnsupportedError('Unsupported text stream filter: $name.');
      }
      bytes = Uint8List.fromList(zlib.decode(bytes!));
    }
    return bytes!;
  }

  /// [decoder] is mandatory because PDF strings contain character codes,
  /// which cannot generally be interpreted as Latin-1 or UTF-8.
  static String fromContent(Uint8List bytes,
      {required PdfCharacterDecoder decoder}) {
    return _contentParts(bytes, decoder: decoder).join();
  }

  static List<Object> _contentParts(Uint8List bytes,
      {required PdfCharacterDecoder decoder,
      _FontBinding? inheritedFont,
      bool allowForms = false,
      Map<String, Object>? properties,
      bool suppressed = false}) {
    final lexer = _ContentTokens(bytes, allowDictionaries: true);
    final operands = <Object>[];
    final output = <Object>[];
    var inText = false;
    var font = inheritedFont;
    final savedFonts = <_FontBinding?>[];
    final marked = <String?>[];
    bool hidden() => suppressed || marked.any((value) => value != null);
    void emit(String value) {
      if (!hidden()) output.add(value);
    }

    void show(Object value) {
      if (!inText || font == null || value is! Uint8List) {
        throw FormatException('Text operator has invalid state or operands.');
      }
      if (!hidden()) output.add(font.decoder(font.name, value));
    }

    while (!lexer.done) {
      final token = lexer.next();
      if (token == null) break;
      if (token is! _Operator) {
        operands.add(token);
        continue;
      }
      switch (token.value) {
        case 'BT':
          if (inText) throw FormatException('Nested text object.');
          inText = true;
        case 'ET':
          if (!inText) throw FormatException('Unexpected ET.');
          inText = false;
        case 'Tf':
          if (operands.length != 2 ||
              operands[0] is! _Name ||
              operands[1] is! num) {
            throw FormatException('Invalid Tf operands.');
          }
          font = _FontBinding((operands[0] as _Name).value, decoder);
        case 'Tj':
        case "'":
          if (operands.length != 1)
            throw FormatException('Invalid text operands.');
          if (token.value == "'") emit('\n');
          show(operands.single);
        case '"':
          if (operands.length != 3 ||
              operands[0] is! num ||
              operands[1] is! num) {
            throw FormatException('Invalid double-quote operands.');
          }
          emit('\n');
          show(operands[2]);
        case 'TJ':
          if (operands.length != 1 || operands.single is! List<Object>) {
            throw FormatException('Invalid TJ operands.');
          }
          for (final item in operands.single as List<Object>) {
            if (item is num) continue;
            show(item);
          }
        case 'T*':
          emit('\n');
        case 'q':
          savedFonts.add(font);
        case 'Q':
          if (savedFonts.isEmpty) throw FormatException('Unbalanced Q.');
          font = savedFonts.removeLast();
        case 'Do':
          if (!allowForms) {
            throw UnsupportedError('Text extraction cannot interpret Do.');
          }
          if (inText || operands.length != 1 || operands.single is! _Name) {
            throw FormatException('Invalid XObject invocation.');
          }
          output.add(_FormInvocation(
              (operands.single as _Name).value, font, hidden()));
        case 'BMC':
          if (operands.length != 1 || operands.single is! _Name) {
            throw FormatException('BMC requires a marked-content tag.');
          }
          if (marked.length >= 128)
            throw FormatException('Marked content is too deeply nested.');
          marked.add(null);
        case 'BDC':
          if (operands.length != 2 || operands.first is! _Name) {
            throw FormatException('BDC requires a tag and property list.');
          }
          Object? property = operands[1];
          if (property is _Name) {
            if (properties == null)
              throw UnsupportedError(
                  'Named marked-content properties require page resources.');
            property = properties[property.value];
          }
          if (property is! Map<String, Object>) {
            throw FormatException(
                'Marked-content property list must be a dictionary.');
          }
          final replacement = property['ActualText'];
          String? text;
          if (replacement is Uint8List) {
            text = _replacementText(replacement);
          } else if (replacement is CraftPdfString) {
            text =
                _replacementText(replacement.getValueBytes() ?? Uint8List(0));
          } else if (replacement != null) {
            throw FormatException('ActualText must be a PDF text string.');
          }
          if (marked.length >= 128)
            throw FormatException('Marked content is too deeply nested.');
          marked.add(text);
        case 'EMC':
          if (operands.isNotEmpty || marked.isEmpty) {
            throw FormatException('Unbalanced marked-content terminator.');
          }
          final replacement = marked.removeLast();
          if (replacement != null) emit(replacement);
        case 'BI':
        case 'DP':
        case 'gs':
          throw UnsupportedError(
              'Text extraction cannot interpret ${token.value}.');
        default:
          if (!const {
            'cm',
            'Td',
            'TD',
            'Tm',
            'Tc',
            'Tw',
            'Tz',
            'TL',
            'Tr',
            'Ts',
            'w',
            'J',
            'j',
            'M',
            'd',
            'ri',
            'i',
            'm',
            'l',
            'c',
            'v',
            'y',
            'h',
            're',
            'S',
            's',
            'f',
            'F',
            'f*',
            'B',
            'B*',
            'b',
            'b*',
            'n',
            'W',
            'W*',
            'CS',
            'cs',
            'SC',
            'SCN',
            'sc',
            'scn',
            'G',
            'g',
            'RG',
            'rg',
            'K',
            'k',
            'sh',
            'MP'
          }.contains(token.value)) {
            throw UnsupportedError('Unknown content operator: ${token.value}.');
          }
      }
      operands.clear();
    }
    if (inText ||
        savedFonts.isNotEmpty ||
        operands.isNotEmpty ||
        marked.isNotEmpty) {
      throw FormatException('Unterminated content state.');
    }
    return output;
  }
}

class _FontBinding {
  final String name;
  final PdfCharacterDecoder decoder;
  _FontBinding(this.name, this.decoder);
}

class _FormInvocation {
  final String name;
  final _FontBinding? font;
  final bool suppressed;
  _FormInvocation(this.name, this.font, this.suppressed);
}

class _Name {
  final String value;
  _Name(this.value);
}

class _Operator {
  final String value;
  _Operator(this.value);
}

class _ContentTokens {
  final Uint8List bytes;
  var position = 0;
  final bool allowDictionaries;
  int _compoundDepth = 0;
  _ContentTokens(this.bytes, {this.allowDictionaries = false});
  bool get done => position >= bytes.length;
  bool space(int c) => const [0, 9, 10, 12, 13, 32].contains(c);
  bool delimiter(int c) =>
      space(c) || const [40, 41, 60, 62, 91, 93, 123, 125, 47, 37].contains(c);
  Object? next() {
    while (!done) {
      if (space(bytes[position])) {
        position++;
        continue;
      }
      if (bytes[position] == 37) {
        while (!done && bytes[position] != 10 && bytes[position] != 13) {
          position++;
        }
        continue;
      }
      break;
    }
    if (done) return null;
    final first = bytes[position++];
    if (first == 40) {
      final result = <int>[];
      var depth = 1;
      while (!done) {
        var c = bytes[position++];
        if (c == 92) {
          if (done) throw FormatException('Incomplete string escape.');
          c = bytes[position++];
          if (c == 10) continue;
          if (c == 13) {
            if (!done && bytes[position] == 10) position++;
            continue;
          }
          if (c >= 48 && c <= 55) {
            var value = c - 48;
            for (var i = 0;
                i < 2 &&
                    !done &&
                    bytes[position] >= 48 &&
                    bytes[position] <= 55;
                i++) {
              value = value * 8 + bytes[position++] - 48;
            }
            result.add(value & 255);
          } else {
            result
                .add(const {110: 10, 114: 13, 116: 9, 98: 8, 102: 12}[c] ?? c);
          }
          continue;
        }
        if (c == 40) depth++;
        if (c == 41 && --depth == 0) return Uint8List.fromList(result);
        if (c == 13) {
          if (!done && bytes[position] == 10) position++;
          c = 10;
        }
        result.add(c);
      }
      throw FormatException('Unterminated string.');
    }
    if (first == 60) {
      if (!done && bytes[position] == 60) {
        if (!allowDictionaries)
          throw UnsupportedError('Inline dictionaries are not supported.');
        position++;
        if (++_compoundDepth > 128)
          throw FormatException('Inline dictionary nesting limit exceeded.');
        final entries = <String, Object>{};
        while (true) {
          final key = next();
          if (key is _Operator && key.value == '>>') break;
          if (key is! _Name)
            throw FormatException('Inline dictionary requires name keys.');
          final value = next();
          if (value == null || value is _Operator)
            throw FormatException('Invalid inline dictionary value.');
          if (entries.containsKey(key.value))
            throw FormatException('Duplicate inline property.');
          entries[key.value] = value;
        }
        _compoundDepth--;
        return entries;
      }
      final digits = StringBuffer();
      while (!done && bytes[position] != 62) {
        final c = bytes[position++];
        if (!space(c)) digits.writeCharCode(c);
      }
      if (done) throw FormatException('Unterminated hexadecimal string.');
      position++;
      var hex = digits.toString();
      if (hex.length.isOdd) hex += '0';
      return Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16)
      ]);
    }
    if (first == 62 && !done && bytes[position] == 62) {
      position++;
      return _Operator('>>');
    }
    if (first == 91) {
      if (allowDictionaries && ++_compoundDepth > 128) {
        throw FormatException('Content composite nesting limit exceeded.');
      }
      final values = <Object>[];
      while (true) {
        final value = next();
        if (value is _Operator && value.value == ']') {
          if (allowDictionaries) _compoundDepth--;
          return values;
        }
        if (value == null || value is _Operator)
          throw FormatException('Invalid content array.');
        values.add(value);
      }
    }
    if (first == 93) return _Operator(']');
    final start = position;
    if (first == 47) {
      while (!done && !delimiter(bytes[position])) {
        position++;
      }
      final name = latin1.decode(bytes.sublist(start, position));
      return _Name(name.replaceAllMapped(RegExp(r'#([0-9a-fA-F]{2})'),
          (m) => String.fromCharCode(int.parse(m[1]!, radix: 16))));
    }
    while (!done && !delimiter(bytes[position])) {
      position++;
    }
    final word = latin1.decode(bytes.sublist(start - 1, position));
    if (allowDictionaries && (word == 'true' || word == 'false'))
      return word == 'true';
    if (allowDictionaries && word == 'null') return const _ContentNull();
    return RegExp(r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$').hasMatch(word)
        ? num.parse(word)
        : _Operator(word);
  }
}

class _ContentNull {
  const _ContentNull();
}
