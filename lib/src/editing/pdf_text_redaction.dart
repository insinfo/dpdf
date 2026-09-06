part of 'pdf_text_extraction.dart';

/// Removes every occurrence of [text] from one page's content-stream order.
/// Page numbers start at 1. Matching is case-sensitive and may span Tj/TJ.
class PdfTextRemoval {
  final int page;
  final String text;
  const PdfTextRemoval(this.page, this.text);
}

/// Replaces all original occurrences on a 1-based page, without reflow.
class PdfTextReplacement extends PdfTextRemoval {
  final String replacement;
  const PdfTextReplacement(super.page, super.text, this.replacement);
}

/// Text replacement in the same strict subset as [PdfTextRedaction].
/// Remaining text retains its positions; longer replacements may overlap it.
class PdfTextEditing {
  static Future<Uint8List> replace(
          Uint8List source, List<PdfTextReplacement> requests) =>
      PdfTextRedaction._rewrite(source, requests, replacementMode: true);
}

/// Structural text removal for an explicitly restricted PDF subset.
///
/// Accepts only text-only pages using nonembedded Courier or Helvetica Type1 fonts,
/// Standard/WinAnsi characters, horizontal text and the operators of PdfTextPositions.
/// Forms, images, annotations, tags, metadata, unknown dictionary entries,
/// arbitrary encodings and non-fill text rendering are rejected.
///
/// Every page is reconstructed in a fresh document with new resources. Source
/// revisions, unused objects, comments and original content streams are never
/// copied. Removed characters become numeric TJ advances, preserving the
/// positions of surviving characters. This is not rectangle/ink redaction.
class PdfTextRedaction {
  static Future<Uint8List> remove(
          Uint8List source, List<PdfTextRemoval> requests) =>
      _rewrite(source, requests);

  static Future<Uint8List> _rewrite(
      Uint8List source, List<PdfTextRemoval> requests,
      {bool replacementMode = false}) async {
    if (requests.isEmpty)
      throw ArgumentError('At least one text removal is required.');
    for (final request in requests) {
      if (request.text.isEmpty ||
          request.text.codeUnits
              .any((c) => c < 32 || (c >= 0xd800 && c <= 0xdfff))) {
        throw ArgumentError(
            'Removal text must be nonempty printable BMP text.');
      }
    }
    final reader = CraftPdfReader.fromBytes(source);
    final input = await CraftPdfDocument.open(reader);
    try {
      if (reader.encrypted)
        throw UnsupportedError('Encrypted redaction is unsupported.');
      _keys(input.rootCatalog().pdfRepresentation(),
          {'Type', 'Pages', 'Version'}, 'catalog');
      final info = await input.fileTrailer().dictionaryEntry(CraftPdfName.info);
      if (info != null && info.size() != 0)
        throw UnsupportedError('Document metadata is unsupported.');
      final count = input.pageTotal();
      for (final request in requests) {
        if (request.page < 1 || request.page > count)
          throw RangeError.range(request.page, 1, count, 'page');
      }
      final plans = <({
        CraftPdfArray media,
        CraftPdfArray? crop,
        int rotate,
        Uint8List content,
        Map<String, ({String encoding, String baseFont})> fonts
      })>[];
      for (var n = 1; n <= count; n++) {
        final page = (await input.pageAt(n))!;
        _keys(
            page.pdfRepresentation(),
            {
              'Type',
              'Parent',
              'MediaBox',
              'CropBox',
              'Rotate',
              'Resources',
              'Contents'
            },
            'page');
        final resources =
            await _inherited(page.pdfRepresentation(), 'Resources');
        if (resources is! CraftPdfDictionary)
          throw UnsupportedError('Page resources are required.');
        _keys(resources, {'Font', 'ProcSet'}, 'resources');
        final fonts = await resources.dictionaryEntry(CraftPdfName.font);
        if (fonts == null || fonts.size() == 0) {
          throw UnsupportedError('At least one text font is required.');
        }
        final fontPlans = <String, ({String encoding, String baseFont})>{};
        for (final resourceName in fonts.getMap()!.keys) {
          final font = await fonts.dictionaryEntry(resourceName);
          if (font == null) throw FormatException('Invalid font dictionary.');
          _keys(font, {'Type', 'Subtype', 'BaseFont', 'Encoding'}, 'font');
          final baseFont =
              (await font.nameEntry(CraftPdfName.baseFont))?.getValue();
          if ((await font.nameEntry(CraftPdfName.subtype))?.getValue() !=
                  'Type1' ||
              !{'Courier', 'Helvetica'}.contains(baseFont)) {
            throw UnsupportedError(
                'Only nonembedded Type1 Courier or Helvetica is supported.');
          }
          final encoding = await font.get(CraftPdfName.encoding, true);
          if (encoding != null &&
              (encoding is! CraftPdfName ||
                  !{'WinAnsiEncoding', 'StandardEncoding'}
                      .contains(encoding.getValue()))) {
            throw UnsupportedError('Font encoding is unsupported.');
          }
          fontPlans[resourceName.getValue()] = (
            baseFont: baseFont!,
            encoding: encoding is CraftPdfName
                ? encoding.getValue()
                : 'StandardEncoding'
          );
        }
        final machine = _TextMachine((font, codes) {
          return PdfSimpleEncoding.decode(fontPlans[font]!.encoding, codes);
        }, (font, code) {
          final plan = fontPlans[font]!;
          return PdfStandardFontMetrics.width(
              plan.baseFont, plan.encoding, code);
        }, allowedFonts: fontPlans.keys.toSet());
        final streamCount = await page.contentSegmentCount();
        final contents =
            await page.pdfRepresentation().get(CraftPdfName.contents, true);
        if (contents != null &&
            contents is! CraftPdfStream &&
            contents is! CraftPdfArray) {
          throw FormatException('Invalid page contents.');
        }
        for (var s = 0; s < streamCount; s++) {
          final stream = await page.contentSegmentAt(s);
          if (stream is! CraftPdfStream)
            throw FormatException('Invalid content stream.');
          _keys(stream, {'Length', 'Filter'}, 'content stream');
        }
        final media =
            await _box(await _inherited(page.pdfRepresentation(), 'MediaBox'));
        final cropObject =
            await _inherited(page.pdfRepresentation(), 'CropBox');
        final crop = cropObject == null ? null : await _box(cropObject);
        final rotation = await _inherited(page.pdfRepresentation(), 'Rotate');
        if (rotation != null &&
            (rotation is! CraftPdfNumber || rotation.doubleValue() % 90 != 0)) {
          throw UnsupportedError(
              'Page rotation must be a multiple of 90 degrees.');
        }
        final content = await PdfTextExtraction._strictContent(page);
        final parsed = machine.read(content);
        final text = parsed.characters.map((c) => c.text).join();
        final remove = <int>{};
        final insert = <int, Uint8List>{};
        for (final request in requests.where((r) => r.page == n)) {
          var found = false;
          var offset = 0;
          while (offset <= text.length - request.text.length) {
            final at = text.indexOf(request.text, offset);
            if (at < 0) break;
            offset = at + 1;
            if (parsed.characters[at].textObjectIndex !=
                parsed
                    .characters[at + request.text.length - 1].textObjectIndex) {
              continue;
            }
            found = true;
            if (replacementMode &&
                List.generate(request.text.length, (i) => at + i)
                    .any(remove.contains)) {
              throw ArgumentError('Overlapping text replacements on page $n.');
            }
            if (replacementMode && request is PdfTextReplacement) {
              insert[at] = PdfSimpleEncoding.encode(
                  fontPlans[parsed.characters[at].font]!.encoding,
                  request.replacement);
            }
            remove.addAll(List.generate(request.text.length, (i) => at + i));
          }
          if (!found)
            throw StateError('Requested text was not found on page $n.');
        }
        final fontNames = <String, String>{};
        for (final name in fontPlans.keys) {
          fontNames[name] = 'F${fontNames.length + 1}';
        }
        final result = machine.read(content,
            remove: remove, insert: insert, fontNames: fontNames);
        plans.add((
          media: media,
          crop: crop,
          rotate: rotation is CraftPdfNumber ? rotation.intValue() : 0,
          content: result.content,
          fonts: {
            for (final entry in fontPlans.entries)
              fontNames[entry.key]!: entry.value
          }
        ));
      }
      // No output is allocated until all pages and all requests pass validation.
      final result = BytesBuilder();
      final output = await CraftPdfDocument.create(
          CraftPdfWriter.fromBytesBuilder(result));
      for (final plan in plans) {
        final page = await output.appendBlankPage();
        final dictionary = page.pdfRepresentation();
        dictionary.put(CraftPdfName.mediaBox, plan.media);
        if (plan.crop != null) dictionary.put(CraftPdfName.cropBox, plan.crop!);
        page.setRotationDegrees(plan.rotate);
        final fonts = CraftPdfDictionary();
        for (final entry in plan.fonts.entries) {
          final font = CraftPdfDictionary()
            ..put(CraftPdfName.type, CraftPdfName.font)
            ..put(CraftPdfName.subtype, CraftPdfName('Type1'))
            ..put(CraftPdfName.baseFont, CraftPdfName(entry.value.baseFont))
            ..put(CraftPdfName.encoding, CraftPdfName(entry.value.encoding));
          fonts.put(CraftPdfName(entry.key), font);
        }
        dictionary.put(CraftPdfName.resources,
            CraftPdfDictionary()..put(CraftPdfName.font, fonts));
        dictionary.put(
            CraftPdfName.contents, CraftPdfStream.withBytes(plan.content, 0));
      }
      (await output.documentDetails()).pdfRepresentation().clear();
      await output.close();
      return result.takeBytes();
    } finally {
      await input.close();
    }
  }

  static void _keys(
      CraftPdfDictionary dict, Set<String> accepted, String context) {
    for (final name in dict.getMap()!.keys) {
      if (!accepted.contains(name.getValue())) {
        throw UnsupportedError(
            'Unsupported $context entry: /${name.getValue()}.');
      }
    }
  }

  static Future<Object?> _inherited(
      CraftPdfDictionary page, String name) async {
    CraftPdfDictionary? node = page;
    final visited = <CraftPdfDictionary>{};
    while (node != null) {
      if (!visited.add(node)) throw FormatException('Cyclic page tree.');
      final value = await node.get(CraftPdfName(name), true);
      if (value != null) return value;
      node = await node.dictionaryEntry(CraftPdfName.parent);
    }
    return null;
  }

  static Future<CraftPdfArray> _box(Object? object) async {
    if (object is! CraftPdfArray || object.size() != 4)
      throw FormatException('Invalid page box.');
    final values = <double>[];
    for (var i = 0; i < 4; i++) {
      final number = await object.get(i);
      if (number is! CraftPdfNumber || !number.doubleValue().isFinite)
        throw FormatException('Invalid page box coordinate.');
      values.add(number.doubleValue());
    }
    if (values[2] <= values[0] || values[3] <= values[1])
      throw FormatException('Empty page box.');
    return CraftPdfArray.fromDoubles(values);
  }
}
