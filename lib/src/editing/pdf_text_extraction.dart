import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../platform/compression.dart';
import 'pdf_unicode_cmap.dart';
import '../io/font/pdf_encodings.dart';
import '../io/font/true_type_font.dart';
import 'pdf_simple_encoding.dart';
import 'pdf_standard_font_metrics.dart';
import 'pdf_encoding_differences.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_page.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/pdf_writer.dart';
import '../render/content_parser.dart';
import '../render/image_decoder.dart';

part 'pdf_text_positions.dart';
part 'pdf_text_redaction.dart';
part 'pdf_graphics_envelope.dart';
part 'pdf_area_redaction.dart';
part 'pdf_inline_image.dart';
part 'pdf_vector_redaction.dart';

/// Decodes PDF character codes for a selected font resource.
/// A decoder must apply that font's Encoding/ToUnicode mapping.
typedef PdfCharacterDecoder = String Function(String font, Uint8List codes);

/// Extracts text in content-stream order, not visual reading order.
///
/// Form XObjects are visited in painting order. Marked-content replacement
/// text is emitted once per sequence. Inline images (`BI ... ID ... EI`,
/// 8.9.7) carry no text, so they are stepped over; their binary payload is
/// bounded by the declared sample count when unfiltered and by a validated
/// `EI` search otherwise, so image bytes are never mistaken for operators.
class PdfTextExtraction {
  /// U+FFFD REPLACEMENT CHARACTER, emitted for a glyph the document draws but
  /// never identifies. It stands in for the one thing a reader may honestly
  /// say about such a glyph: a character was here and the file does not name
  /// it. Guessing a letter instead would be indistinguishable from the real
  /// text downstream; dropping it silently would hide that anything was lost.
  static const int _undefinedCharacter = 0xfffd;

  static Future<String> fromPage(PdfPage page,
      {PdfCharacterDecoder? decoder}) async {
    var resources =
        await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
    PdfDictionary? parent = page.pdfRepresentation();
    final visited = <PdfDictionary>{};
    while (resources == null && parent != null && visited.add(parent)) {
      parent = await parent.dictionaryEntry(PdfName.parent);
      resources = await parent?.dictionaryEntry(PdfName.resources);
    }
    return _fromResources(
        await _strictContent(page), resources, decoder, <PdfStream>{}, null);
  }

  static Future<String> _fromResources(
      Uint8List bytes,
      PdfDictionary? resources,
      PdfCharacterDecoder? customDecoder,
      Set<PdfStream> activeForms,
      _FontBinding? inheritedFont,
      {bool suppressed = false}) async {
    final decoder = customDecoder ?? await _resourceDecoder(resources);
    final propertyValues = <String, Object>{};
    final properties = await resources?.dictionaryEntry(PdfName('Properties'));
    if (properties != null) {
      for (final entry in await properties.entrySet()) {
        final property = await properties.get(entry.key, true);
        if (property is PdfDictionary) {
          final replacement = await property.get(PdfName('ActualText'), true);
          propertyValues[entry.key.getValue()] = replacement == null
              ? <String, Object>{}
              : <String, Object>{'ActualText': replacement};
        } else {
          propertyValues[entry.key.getValue()] = false;
        }
      }
    }
    final textStates = <String, bool>{};
    final states = await resources?.dictionaryEntry(PdfName('ExtGState'));
    if (states != null) {
      for (final entry in await states.entrySet()) {
        final state = await states.get(entry.key, true);
        if (state is! PdfDictionary) {
          throw FormatException('An /ExtGState entry must be a dictionary.');
        }
        textStates[entry.key.getValue()] = state.containsKey(PdfName.font);
      }
    }
    final parts = _contentParts(bytes,
        decoder: decoder,
        inheritedFont: inheritedFont,
        allowForms: true,
        properties: propertyValues,
        graphicsStates: textStates,
        suppressed: suppressed);
    final output = StringBuffer();
    for (final part in parts) {
      if (part is String) {
        output.write(part);
        continue;
      }
      final invocation = part as _FormInvocation;
      final objects = await resources?.dictionaryEntry(PdfName('XObject'));
      final object = await objects?.get(PdfName(invocation.name), true);
      if (object is! PdfStream) {
        throw FormatException('Missing XObject stream /${invocation.name}.');
      }
      final subtype = (await object.nameEntry(PdfName.subtype))?.getValue();
      if (subtype == 'Image') continue;
      if (subtype != 'Form') {
        throw UnsupportedError('Unsupported XObject subtype: $subtype.');
      }
      if (activeForms.length >= 128 || !activeForms.add(object)) {
        throw FormatException(
            'Recursive or excessively nested Form XObject /${invocation.name}.');
      }
      try {
        final local = await object.get(PdfName.resources, true);
        if (local != null && local is! PdfDictionary) {
          throw FormatException('Form resources must be a dictionary.');
        }
        output.write(await _fromResources(
            await _strictStream(object),
            local as PdfDictionary? ?? resources,
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
      if (bytes.length.isOdd) {
        throw FormatException('ActualText has incomplete UTF-16 data.');
      }
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
    return PdfEncodings.convertToString(bytes, 'PDF');
  }

  /// Byte width of the character codes a font produces, or null when only the
  /// font's own CMap could say. Simple fonts always use single-byte codes
  /// (9.6.6.1); Identity-H/V always use two (9.7.5.2). Every other composite
  /// encoding names a CMap this reader does not execute, so its ToUnicode
  /// stream keeps having to speak for itself.
  static int? _codeLength(String? subtype, String? encoding) {
    if (subtype == 'Type1' ||
        subtype == 'MMType1' ||
        subtype == 'TrueType' ||
        subtype == 'Type3') {
      return 1;
    }
    if (subtype == 'Type0' &&
        (encoding == 'Identity-H' || encoding == 'Identity-V')) {
      return 2;
    }
    return null;
  }

  /// Flag 3 of /FontDescriptor /Flags (9.8.2, Table 123): the font's character
  /// set lies outside the Adobe standard Latin set.
  static Future<bool> _isSymbolic(PdfDictionary? font) async {
    final descriptor = await font?.dictionaryEntry(PdfName('FontDescriptor'));
    final flags = await descriptor?.get(PdfName('Flags'), true);
    if (flags == null) return false;
    if (flags is! PdfNumber) {
      throw FormatException('/FontDescriptor /Flags must be a number.');
    }
    return flags.intValue() & 4 != 0;
  }

  /// Glyph index to Unicode scalar, read back out of an embedded TrueType
  /// program, for an Identity-H/V font that ships no ToUnicode CMap.
  ///
  /// With Identity encoding and an Identity /CIDToGIDMap the character codes
  /// are glyph indices, and nothing in the PDF says what those glyphs mean.
  /// The font's own `cmap` table does: it is the font declaring which
  /// character each glyph draws, so reading it backwards reports the font's
  /// statement rather than a guess of ours. When several characters share one
  /// glyph — U+0020 and U+00A0, U+002D and U+00AD — the lowest scalar wins:
  /// the higher ones are the compatibility aliases of the lower one, so the
  /// choice is between spellings of the same character, not between different
  /// characters.
  ///
  /// The producers of subset Identity fonts routinely drop the `cmap` table,
  /// since the viewer indexes glyphs directly and never needs it. Then the
  /// document states nowhere at all what its glyphs mean, and the returned
  /// map is simply empty: the caller marks those codes [_undefinedCharacter]
  /// rather than dropping the page, because the missing information is the
  /// file's, not this reader's. That is the whole of the relaxation — null
  /// comes back whenever the chain breaks for a reason that could instead be
  /// read (a /CIDToGIDMap stream, a CFF descendant, a font that is not
  /// embedded at all), and such a font keeps being refused outright.
  static Future<Map<int, int>?> _embeddedGlyphUnicode(
      PdfDictionary font) async {
    final descendants = await font.get(PdfName('DescendantFonts'), true);
    if (descendants is! PdfArray || descendants.size() != 1) return null;
    final descendant = await descendants.get(0, true);
    if (descendant is! PdfDictionary) return null;
    final kind = (await descendant.nameEntry(PdfName.subtype))?.getValue();
    if (kind != 'CIDFontType0' && kind != 'CIDFontType2') return null;
    if (kind == 'CIDFontType2') {
      // A /CIDToGIDMap stream would renumber the glyphs, and this reader does
      // not apply it, so only the identity case may be read back.
      final cidToGid = await descendant.get(PdfName('CIDToGIDMap'), true);
      if (cidToGid != null &&
          !(cidToGid is PdfName && cidToGid.getValue() == 'Identity')) {
        return null;
      }
    }
    // Any ordering other than Identity names a registered character
    // collection whose CIDs do carry meaning, through tables this reader does
    // not consult here. Such a font is refused, not declared meaningless.
    final systemInfo =
        await descendant.dictionaryEntry(PdfName('CIDSystemInfo'));
    final ordering = await systemInfo?.get(PdfName('Ordering'), true);
    final identityOrdering =
        ordering is PdfString && ordering.getValue() == 'Identity';
    final descriptor =
        await descendant.dictionaryEntry(PdfName('FontDescriptor'));
    var program = await descriptor?.streamEntry(PdfName('FontFile2'));
    var bareCff = false;
    if (program == null) {
      program = await descriptor?.streamEntry(PdfName('FontFile3'));
      // A bare CFF font program has no place to put a character map: the
      // format has no `cmap` table, and a CID-keyed charset lists CIDs, not
      // characters. Wrapped in OpenType it can carry one, so that is read.
      bareCff = program != null &&
          (await program.nameEntry(PdfName.subtype))?.getValue() != 'OpenType';
    }
    final bytes = await program?.getBytes();
    if (bytes == null || bytes.isEmpty) return null;
    if (bareCff) return identityOrdering ? const {} : null;
    final tables = _sfntTables(bytes);
    if (tables == null) return null;
    if (!tables.contains('cmap')) {
      return identityOrdering ? const {} : null;
    }
    final TrueTypeFont parsed;
    try {
      parsed = TrueTypeFont.fromBytes(bytes);
    } catch (_) {
      return null;
    }
    final reverse = <int, int>{};
    parsed.unicodeToGlyph.forEach((scalar, glyph) {
      if (scalar < 0) return;
      final glyphIndex = glyph.getCode();
      final previous = reverse[glyphIndex];
      if (previous == null || scalar < previous) reverse[glyphIndex] = scalar;
    });
    return reverse;
  }

  /// Tags of an sfnt table directory, or null if [bytes] is not one font's
  /// own sfnt. A collection is excluded on purpose: which of its fonts the
  /// stream means is a question this reader does not answer.
  static Set<String>? _sfntTables(Uint8List bytes) {
    if (bytes.length < 12) return null;
    final view = ByteData.sublistView(bytes);
    const sfntVersions = {0x00010000, 0x4f54544f, 0x74727565};
    if (!sfntVersions.contains(view.getUint32(0))) return null;
    final count = view.getUint16(4);
    if (12 + count * 16 > bytes.length) return null;
    return {
      for (var i = 0; i < count; i++)
        latin1.decode(bytes.sublist(12 + i * 16, 16 + i * 16))
    };
  }

  static Future<PdfCharacterDecoder> _resourceDecoder(
      PdfDictionary? resources) async {
    final fonts = await resources?.dictionaryEntry(PdfName.font);
    final decodings = <String, _FontDecoding>{};
    if (fonts != null) {
      for (final entry in await fonts.entrySet()) {
        final font = await fonts.dictionaryEntry(entry.key);
        if (font == null) continue;
        decodings[entry.key.getValue()] = await _fontDecoding(font);
      }
    }
    return (font, codes) {
      final decoding = decodings[font];
      if (decoding == null) {
        throw UnsupportedError('A character decoder is required for /$font.');
      }
      return decoding.decode(font, codes);
    };
  }

  /// Collects every source one font offers for recovering text, in the order
  /// 9.10.2 ranks them: the ToUnicode CMap first, then the encoding the font
  /// declares. Both are read, not just the first one present, because a
  /// ToUnicode CMap is routinely partial — a producer that emits WinAnsi text
  /// and one en dash writes a CMap holding only the en dash, and every other
  /// code is meant to be read off the encoding.
  static Future<_FontDecoding> _fontDecoding(PdfDictionary font) async {
    final base = (await font.nameEntry(PdfName.baseFont))?.getValue();
    final subtype = (await font.nameEntry(PdfName.subtype))?.getValue();
    final encoding = (await font.nameEntry(PdfName.encoding))?.getValue();
    final codeLength = _codeLength(subtype, encoding);

    PdfUnicodeCMap? unicode;
    final toUnicode = await font.get(PdfName('ToUnicode'), true);
    if (toUnicode != null) {
      if (toUnicode is! PdfStream) {
        throw FormatException('ToUnicode must be a stream.');
      }
      if (toUnicode.containsKey(PdfName('UseCMap'))) {
        throw UnsupportedError('Inherited ToUnicode CMaps are unsupported.');
      }
      unicode = PdfUnicodeCMap.parse(await _strictStream(toUnicode),
          codeLength: codeLength);
    }

    if (subtype == 'Type0') {
      return _FontDecoding(
          codeLength: codeLength,
          unicode: unicode,
          glyphUnicode: encoding == 'Identity-H' || encoding == 'Identity-V'
              ? await _embeddedGlyphUnicode(font)
              : null);
    }

    // With a ToUnicode CMap in hand the encoding is only a backstop for the
    // codes the CMap omits, so a broken /Encoding no longer sinks the font:
    // the primary source still answers, and codes it does not cover fall to
    // the replacement character. Without a CMap the encoding is the only
    // source there is, and its errors are the font's errors.
    try {
      return await _declaredEncoding(font, subtype, encoding, codeLength,
          base: base, unicode: unicode);
    } catch (_) {
      if (unicode == null) rethrow;
      return _FontDecoding(codeLength: codeLength, unicode: unicode);
    }
  }

  static Future<_FontDecoding> _declaredEncoding(
      PdfDictionary font, String? subtype, String? encoding, int? codeLength,
      {String? base, PdfUnicodeCMap? unicode}) async {
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
    final encodingObject = await font.get(PdfName.encoding, true);
    if (encodingObject is PdfDictionary &&
        (subtype == 'Type1' || subtype == 'TrueType' || subtype == 'Type3')) {
      return _FontDecoding(
          codeLength: codeLength,
          unicode: unicode,
          differences: await PdfEncodingDifferences.parse(encodingObject,
              defaultBase: latinBase14 ? 'StandardEncoding' : null));
    }
    if (latinBase14 &&
        (encodingObject == null ||
            encoding == 'WinAnsiEncoding' ||
            encoding == 'StandardEncoding')) {
      return _FontDecoding(
          codeLength: codeLength,
          unicode: unicode,
          baseEncoding: encoding ?? 'StandardEncoding');
    }
    // A named base encoding (9.6.6.2, Annex D) assigns a glyph name to every
    // code on its own, so an embedded subset with no ToUnicode is still
    // decodable: the font program supplies outlines, not meaning. Only the
    // flat Latin tables qualify. A symbolic TrueType font takes its encoding
    // from the font program's own cmap (9.6.6.4), so a base encoding name on
    // one is not authoritative and is not trusted here; and a font with no
    // /Encoding at all falls back to the built-in encoding this reader does
    // not read, so it keeps being refused.
    if ((subtype == 'Type1' || subtype == 'MMType1' || subtype == 'TrueType') &&
        const {'WinAnsiEncoding', 'MacRomanEncoding', 'StandardEncoding'}
            .contains(encoding) &&
        !await _isSymbolic(font)) {
      return _FontDecoding(
          codeLength: codeLength, unicode: unicode, baseEncoding: encoding);
    }
    return _FontDecoding(codeLength: codeLength, unicode: unicode);
  }

  static Future<Uint8List> _strictContent(PdfPage page) async {
    final result = BytesBuilder();
    final contents = await page.pdfRepresentation().get(PdfName.contents, true);
    if (contents != null && contents is! PdfStream && contents is! PdfArray) {
      throw FormatException('Page contents must be a stream or array.');
    }
    final count = await page.contentSegmentCount();
    for (var i = 0; i < count; i++) {
      final object = await page.contentSegmentAt(i);
      if (object is! PdfStream) {
        throw FormatException('Page contents must resolve to streams.');
      }
      final bytes = await _strictStream(object);
      result.add(bytes);
      result.addByte(10);
    }
    return result.takeBytes();
  }

  static Future<Uint8List> _strictStream(PdfStream object) async {
    if (object.containsKey(PdfName('DecodeParms'))) {
      throw UnsupportedError(
          'Content-stream decode parameters require a dedicated decoder.');
    }
    var bytes = await object.getBytes(false);
    if (bytes == null) throw FormatException('Missing stream bytes.');
    final filter = await object.get(PdfName.filter, true);
    final names = <String>[];
    if (filter is PdfName) {
      names.add(filter.getValue());
    } else if (filter is PdfArray) {
      for (var j = 0; j < filter.size(); j++) {
        final name = await filter.get(j);
        if (name is! PdfName) {
          throw FormatException('Invalid stream filter.');
        }
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
      Map<String, bool>? graphicsStates,
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

    Map<String, Object> propertyList(Object operand) {
      Object? property = operand;
      if (property is _Name) {
        if (properties == null) {
          throw UnsupportedError(
              'Named marked-content properties require page resources.');
        }
        property = properties[property.value];
      }
      if (property is! Map<String, Object>) {
        throw FormatException(
            'Marked-content property list must be a dictionary.');
      }
      return property;
    }

    String? actualText(Map<String, Object> property) {
      final replacement = property['ActualText'];
      if (replacement is Uint8List) return _replacementText(replacement);
      if (replacement is PdfString) {
        return _replacementText(replacement.getValueBytes() ?? Uint8List(0));
      }
      if (replacement != null) {
        throw FormatException('ActualText must be a PDF text string.');
      }
      return null;
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
          if (operands.length != 1) {
            throw FormatException('Invalid text operands.');
          }
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
          if (marked.length >= 128) {
            throw FormatException('Marked content is too deeply nested.');
          }
          marked.add(null);
        case 'BDC':
          if (operands.length != 2 || operands.first is! _Name) {
            throw FormatException('BDC requires a tag and property list.');
          }
          final text = actualText(propertyList(operands[1]));
          if (marked.length >= 128) {
            throw FormatException('Marked content is too deeply nested.');
          }
          marked.add(text);
        case 'EMC':
          if (operands.isNotEmpty || marked.isEmpty) {
            throw FormatException('Unbalanced marked-content terminator.');
          }
          final replacement = marked.removeLast();
          if (replacement != null) emit(replacement);
        case 'BI':
          if (inText) {
            throw FormatException(
                'An inline image cannot appear inside a text object.');
          }
          if (operands.isNotEmpty) {
            throw FormatException('BI takes no operands.');
          }
          lexer.readInlineImage();
        case 'DP':
          // DP designates a marked-content *point* (14.6.2), not a sequence:
          // it has no EMC and therefore spans no content. /ActualText replaces
          // "the marked-content sequence" (14.9.4, Table 352), and a point has
          // none to replace, so a reader has nothing it may legally emit here.
          // The point itself is still validated and then dropped, exactly like
          // the MP it extends. A property list that does carry /ActualText is
          // refused rather than silently discarded: the producer clearly meant
          // that text to reach a reader, and this reader cannot place it.
          if (operands.length != 2 || operands.first is! _Name) {
            throw FormatException('DP requires a tag and property list.');
          }
          if (actualText(propertyList(operands[1])) != null) {
            throw UnsupportedError(
                'Text extraction cannot place /ActualText on a DP point.');
          }
        case 'gs':
          // gs installs a graphics state from /ExtGState (8.4.5, Table 58).
          // Only its /Font entry can change extracted text; every other entry
          // is colour, transparency, line or rendering state that no text
          // operator reads. Refusing all of them would refuse nearly every
          // real document, so the dictionary decides.
          if (operands.length != 1 || operands.single is! _Name) {
            throw FormatException('gs requires a graphics state name.');
          }
          final state = (operands.single as _Name).value;
          if (graphicsStates == null) {
            throw UnsupportedError(
                'Resolving gs /$state requires page resources.');
          }
          final hasFont = graphicsStates[state];
          if (hasFont == null) {
            throw FormatException('Missing /ExtGState entry /$state.');
          }
          if (hasFont) {
            throw UnsupportedError(
                'Text extraction cannot interpret gs /$state, whose '
                '/ExtGState carries a /Font entry.');
          }
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
            'MP',
            // Compatibility section brackets (7.8.2). They carry no state and
            // no text; the operators they enclose are still checked one by
            // one, so an unknown operator inside one is not waved through.
            'BX',
            'EX'
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

/// The sources one font resource offers for turning its character codes into
/// text, and the order they are consulted in.
///
/// The order follows 9.10.2: a ToUnicode CMap is the document's direct
/// statement about a code and wins; otherwise the encoding the font declares
/// answers. Anything a source does claim is reported as that source states
/// it, errors included — a glyph name that resolves to nothing, or a byte the
/// encoding leaves undefined, stays an error rather than becoming filler.
///
/// [PdfTextExtraction._undefinedCharacter] is reached only when the sources
/// that exist all fall silent on a code they were entitled to answer, which
/// happens when a producer subsets away the information. A font that offers
/// no source at all is a different matter and is refused outright: there the
/// gap is in this reader, not in the file.
class _FontDecoding {
  /// Bytes per character code, or null when only [unicode] can split the
  /// string, because the font's encoding names a CMap this reader does not
  /// execute. A null width forces the all-or-nothing path: without knowing
  /// where one code ends there is no per-code fallback to try.
  final int? codeLength;
  final PdfUnicodeCMap? unicode;
  final PdfEncodingDifferences? differences;
  final String? baseEncoding;
  final Map<int, int>? glyphUnicode;

  const _FontDecoding(
      {this.codeLength,
      this.unicode,
      this.differences,
      this.baseEncoding,
      this.glyphUnicode});

  bool get _empty =>
      unicode == null &&
      differences == null &&
      baseEncoding == null &&
      glyphUnicode == null;

  String decode(String name, Uint8List codes) {
    final width = codeLength;
    if (_empty || (width == null && unicode == null)) {
      throw UnsupportedError('A character decoder is required for /$name.');
    }
    if (width == null) return unicode!.decode(codes);
    if (codes.length % width != 0) {
      throw FormatException(
          'Text of /$name is not a whole number of $width-byte codes', codes);
    }
    final text = StringBuffer();
    for (var offset = 0; offset < codes.length; offset += width) {
      final code = Uint8List.sublistView(codes, offset, offset + width);
      final mapped = unicode?.textFor(code);
      if (mapped != null) {
        text.write(mapped);
        continue;
      }
      if (differences != null) {
        text.write(differences!.decode(code));
        continue;
      }
      if (baseEncoding != null) {
        text.write(PdfSimpleEncoding.decode(baseEncoding!, code));
        continue;
      }
      final glyphs = glyphUnicode;
      if (glyphs != null) {
        final scalar = glyphs[code.fold<int>(0, (value, b) => value * 256 + b)];
        if (scalar != null) {
          text.writeCharCode(scalar);
          continue;
        }
      }
      text.writeCharCode(PdfTextExtraction._undefinedCharacter);
    }
    return text.toString();
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
        if (!allowDictionaries) {
          throw UnsupportedError('Inline dictionaries are not supported.');
        }
        position++;
        if (++_compoundDepth > 128) {
          throw FormatException('Inline dictionary nesting limit exceeded.');
        }
        final entries = <String, Object>{};
        while (true) {
          final key = next();
          if (key is _Operator && key.value == '>>') break;
          if (key is! _Name) {
            throw FormatException('Inline dictionary requires name keys.');
          }
          final value = next();
          if (value == null || value is _Operator) {
            throw FormatException('Invalid inline dictionary value.');
          }
          if (entries.containsKey(key.value)) {
            throw FormatException('Duplicate inline property.');
          }
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
        if (value == null || value is _Operator) {
          throw FormatException('Invalid content array.');
        }
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
    if (allowDictionaries && (word == 'true' || word == 'false')) {
      return word == 'true';
    }
    if (allowDictionaries && word == 'null') return const _ContentNull();
    return RegExp(r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$').hasMatch(word)
        ? num.parse(word)
        : _Operator(word);
  }
}

class _ContentNull {
  const _ContentNull();
}
