part of 'pdf_text_extraction.dart';

/// One rectangle to redact, in unrotated PDF page user space.
///
/// Page numbers start at 1. The rectangle is the region the caller wants gone;
/// a character is removed when its baseline advance crosses it.
class PdfRedactionArea {
  final int page;

  /// Lower-left and upper-right corners in page user space, in points.
  final double left, bottom, right, top;

  const PdfRedactionArea(
    this.page, {
    required this.left,
    required this.bottom,
    required this.right,
    required this.top,
  });

  /// Builds an area from a rectangle expressed as position plus size.
  factory PdfRedactionArea.fromSize(
    int page, {
    required double x,
    required double y,
    required double width,
    required double height,
  }) =>
      PdfRedactionArea(page,
          left: x, bottom: y, right: x + width, top: y + height);

  bool get isEmpty => right <= left || top <= bottom;

  /// True when the segment from ([x1], [y1]) to ([x2], [y2]) — a character's
  /// baseline advance — passes through this rectangle. The test is on the
  /// segment's own bounding box, widened by [padding] so a glyph whose ink
  /// rises above its baseline still counts.
  bool touchesSegment(
      double x1, double y1, double x2, double y2, double padding) {
    final minX = (x1 < x2 ? x1 : x2) - padding;
    final maxX = (x1 > x2 ? x1 : x2) + padding;
    final minY = (y1 < y2 ? y1 : y2) - padding;
    final maxY = (y1 > y2 ? y1 : y2) + padding;
    return maxX >= left && minX <= right && maxY >= bottom && minY <= top;
  }
}

/// What to do beyond deleting the text inside the areas.
class PdfAreaRedactionOptions {
  /// Paints an opaque rectangle over each area, so the redaction is visible.
  ///
  /// The removal itself is structural: the characters are gone from the
  /// content stream whether or not a box is drawn. The box exists so a reader
  /// can see that something was removed.
  final bool paintOverlay;

  /// Fill colour of the overlay, as red, green and blue in the range 0 to 1.
  final List<double> overlayColor;

  /// Deletes annotations whose /Rect meets a redacted area. Left on by
  /// default: an annotation's contents are text a reader can still surface.
  final bool removeAnnotations;

  /// Clears the document information dictionary, which often repeats content
  /// from the page in /Title, /Subject or /Keywords.
  final bool clearDocumentInfo;

  /// Extra distance in points around a character's baseline advance that still
  /// counts as touching an area. Roughly the ascent of ordinary body text, so
  /// a rectangle drawn around visible glyphs catches them.
  final double glyphPadding;

  const PdfAreaRedactionOptions({
    this.paintOverlay = true,
    this.overlayColor = const [0, 0, 0],
    this.removeAnnotations = true,
    this.clearDocumentInfo = false,
    this.glyphPadding = 2,
  });
}

/// Removes every character drawn inside given rectangles, on documents the
/// strict [PdfTextRedaction] path rejects.
///
/// Unlike that path, this one keeps the document: images, vector art, other
/// pages and the object graph survive, and the page is rewritten in place
/// rather than rebuilt. Characters inside an area are deleted from the content
/// stream and replaced by the advance they occupied, so the surviving text
/// keeps its position.
///
/// What it does not do, and what a caller must not assume:
///
/// * It removes **text**. An image inside the area is covered by the overlay
///   but its pixels stay in the file; redacting a scanned page needs the image
///   itself replaced.
/// * Vector art inside the area is likewise covered, not removed.
/// * Composite (Type0/CID) fonts are rejected, because a single-byte text
///   machine cannot locate their glyphs.
///
/// Use [PdfTextRedaction] when the stricter guarantee — a document rebuilt
/// from nothing but the surviving text — is what you need.
class PdfAreaRedaction {
  /// Applies [areas] to [source] and returns the rewritten document.
  static Future<Uint8List> apply(
    Uint8List source,
    List<PdfRedactionArea> areas, {
    PdfAreaRedactionOptions options = const PdfAreaRedactionOptions(),
  }) async {
    if (areas.isEmpty) {
      throw ArgumentError('At least one redaction area is required.');
    }
    for (final area in areas) {
      if (area.isEmpty) {
        throw ArgumentError('A redaction area must have a positive extent.');
      }
      if (![area.left, area.bottom, area.right, area.top]
          .every((value) => value.isFinite)) {
        throw ArgumentError('Redaction area coordinates must be finite.');
      }
    }
    if (options.overlayColor.length != 3 ||
        options.overlayColor.any((c) => c < 0 || c > 1 || !c.isFinite)) {
      throw ArgumentError('Overlay colour must be three values from 0 to 1.');
    }

    final output = BytesBuilder();
    final document = CraftPdfDocument(
      reader: CraftPdfReader.fromBytes(source),
      writer: CraftPdfWriter.fromBytesBuilder(output),
    );
    await document.load();
    try {
      final pageCount = document.pageTotal();
      for (final area in areas) {
        if (area.page < 1 || area.page > pageCount) {
          throw RangeError.range(area.page, 1, pageCount, 'page');
        }
      }

      final byPage = <int, List<PdfRedactionArea>>{};
      for (final area in areas) {
        byPage.putIfAbsent(area.page, () => []).add(area);
      }

      for (final entry in byPage.entries) {
        final page = (await document.pageAt(entry.key))!;
        await _redactPage(document, page, entry.value, options);
      }

      if (options.clearDocumentInfo) {
        (await document.documentDetails()).pdfRepresentation().clear();
      }
      await document.close();
      return output.takeBytes();
    } catch (_) {
      await document.close().catchError((_) {});
      rethrow;
    }
  }

  static Future<void> _redactPage(
    CraftPdfDocument document,
    CraftPdfPage page,
    List<PdfRedactionArea> areas,
    PdfAreaRedactionOptions options,
  ) async {
    final dictionary = page.pdfRepresentation();
    final resources =
        await PdfTextRedaction._inherited(dictionary, 'Resources');
    final fonts = resources is CraftPdfDictionary
        ? await resources.dictionaryEntry(CraftPdfName.font)
        : null;

    final metrics = await _PageFontMetrics.resolve(fonts);
    final content = await page.contentPayload();

    if (content.isNotEmpty && metrics.hasFonts) {
      final machine = _TextMachine(metrics.decode, metrics.width);
      final parsed = machine.read(content);
      final remove = <int>{};
      for (var index = 0; index < parsed.characters.length; index++) {
        final character = parsed.characters[index];
        for (final area in areas) {
          if (area.touchesSegment(character.x, character.y, character.endX,
              character.endY, options.glyphPadding)) {
            remove.add(index);
            break;
          }
        }
      }
      if (remove.isNotEmpty) {
        final rewritten = machine.read(content, remove: remove);
        final stream = CraftPdfStream.withBytes(rewritten.content, 0);
        stream.attachToDocument(document);
        dictionary.put(CraftPdfName.contents, stream);
        dictionary.markChanged();
      }
    }

    if (options.removeAnnotations) {
      await _removeAnnotations(dictionary, areas);
    }
    if (options.paintOverlay) {
      await _paintOverlay(document, page, areas, options);
    }
  }

  static Future<void> _removeAnnotations(
    CraftPdfDictionary dictionary,
    List<PdfRedactionArea> areas,
  ) async {
    final annotations = await dictionary.arrayEntry(CraftPdfName.annots);
    if (annotations == null) return;

    final survivors = CraftPdfArray();
    for (var i = 0; i < annotations.size(); i++) {
      final annotation = await annotations.dictionaryEntry(i);
      if (annotation == null) continue;
      final rect = await annotation.arrayEntry(CraftPdfName.rect);
      var intersects = false;
      if (rect != null && rect.size() == 4) {
        final values = <double>[];
        for (var j = 0; j < 4; j++) {
          final number = await rect.get(j);
          values.add(number is CraftPdfNumber ? number.doubleValue() : 0);
        }
        final left = values[0] < values[2] ? values[0] : values[2];
        final right = values[0] > values[2] ? values[0] : values[2];
        final bottom = values[1] < values[3] ? values[1] : values[3];
        final top = values[1] > values[3] ? values[1] : values[3];
        intersects = areas.any((area) =>
            right >= area.left &&
            left <= area.right &&
            top >= area.bottom &&
            bottom <= area.top);
      }
      if (!intersects) {
        final original = await annotations.get(i, false);
        if (original != null) survivors.add(original);
      }
    }
    if (survivors.size() == 0) {
      dictionary.remove(CraftPdfName.annots);
    } else {
      dictionary.put(CraftPdfName.annots, survivors);
    }
    dictionary.markChanged();
  }

  static Future<void> _paintOverlay(
    CraftPdfDocument document,
    CraftPdfPage page,
    List<PdfRedactionArea> areas,
    PdfAreaRedactionOptions options,
  ) async {
    final buffer = StringBuffer('q\n');
    final colour = options.overlayColor.map(_pdfNumber).join(' ');
    buffer.writeln('$colour rg');
    for (final area in areas) {
      final x = _pdfNumber(area.left);
      final y = _pdfNumber(area.bottom);
      final width = _pdfNumber(area.right - area.left);
      final height = _pdfNumber(area.top - area.bottom);
      buffer.writeln('$x $y $width $height re');
    }
    buffer
      ..writeln('f')
      ..writeln('Q');

    final overlay = CraftPdfStream.withBytes(
        Uint8List.fromList(latin1.encode(buffer.toString())), 0);
    overlay.attachToDocument(document);

    final dictionary = page.pdfRepresentation();
    final existing = await dictionary.get(CraftPdfName.contents, true);
    if (existing is CraftPdfArray) {
      existing.add(overlay);
      existing.markChanged();
    } else {
      final array = CraftPdfArray();
      if (existing != null) {
        final reference = await dictionary.get(CraftPdfName.contents, false);
        array.add(reference ?? existing);
      }
      array.add(overlay);
      dictionary.put(CraftPdfName.contents, array);
    }
    dictionary.markChanged();
  }
}

/// Per-resource-name character widths and decoding for one page.
///
/// Widths come from the font's own /Widths array when it has one, which covers
/// embedded and subset fonts alike; a font without /Widths falls back to the
/// standard 14 metrics for its base name. This is what lets area redaction
/// work on documents the strict path rejects.
class _PageFontMetrics {
  final Map<String, _FontMetric> _byName;

  const _PageFontMetrics(this._byName);

  bool get hasFonts => _byName.isNotEmpty;

  static Future<_PageFontMetrics> resolve(CraftPdfDictionary? fonts) async {
    if (fonts == null) return const _PageFontMetrics({});
    final resolved = <String, _FontMetric>{};
    for (final key in fonts.keySet()) {
      final font = await fonts.dictionaryEntry(key);
      if (font == null) continue;
      final subtype = (await font.nameEntry(CraftPdfName.subtype))?.getValue();
      if (subtype == 'Type0') {
        throw UnsupportedError(
            'Area redaction does not support the composite font '
            '/${key.getValue()}; its glyph positions need a CMap the '
            'single-byte text machine cannot read.');
      }
      resolved[key.getValue()] = await _FontMetric.resolve(font);
    }
    return _PageFontMetrics(resolved);
  }

  String decode(String font, Uint8List codes) {
    final metric = _byName[font];
    if (metric == null) {
      throw FormatException('Content references the unknown font /$font.');
    }
    return PdfSimpleEncoding.decode(metric.encoding, codes);
  }

  double width(String font, int code) {
    final metric = _byName[font];
    if (metric == null) {
      throw FormatException('Content references the unknown font /$font.');
    }
    return metric.widthOf(code);
  }
}

class _FontMetric {
  final String encoding;
  final String baseFont;
  final int firstChar;
  final List<double> widths;
  final double missingWidth;

  const _FontMetric({
    required this.encoding,
    required this.baseFont,
    required this.firstChar,
    required this.widths,
    required this.missingWidth,
  });

  static Future<_FontMetric> resolve(CraftPdfDictionary font) async {
    final baseFont =
        (await font.nameEntry(CraftPdfName.baseFont))?.getValue() ??
            'Helvetica';
    final encodingObject = await font.get(CraftPdfName.encoding, true);
    var encoding = 'StandardEncoding';
    if (encodingObject is CraftPdfName) {
      encoding = encodingObject.getValue();
    } else if (encodingObject is CraftPdfDictionary) {
      final base = await encodingObject.nameEntry(CraftPdfName.baseEncoding);
      encoding = base?.getValue() ?? 'StandardEncoding';
    }
    if (encoding != 'WinAnsiEncoding' && encoding != 'StandardEncoding') {
      // MacRomanEncoding and the rest share the ASCII range, which is what a
      // width lookup needs; decoding falls back to the standard table.
      encoding = 'StandardEncoding';
    }

    final firstChar = await font.integerEntry(CraftPdfName.firstChar) ?? 0;
    final widthArray = await font.arrayEntry(CraftPdfName.widths);
    final widths = <double>[];
    if (widthArray != null) {
      for (var i = 0; i < widthArray.size(); i++) {
        final number = await widthArray.get(i);
        widths.add(number is CraftPdfNumber ? number.doubleValue() : 0);
      }
    }
    final descriptor = await font.dictionaryEntry(CraftPdfName.fontDescriptor);
    final missing =
        await descriptor?.decimalEntry(CraftPdfName('MissingWidth')) ?? 0;

    return _FontMetric(
      encoding: encoding,
      baseFont: baseFont,
      firstChar: firstChar,
      widths: widths,
      missingWidth: missing,
    );
  }

  double widthOf(int code) {
    if (widths.isNotEmpty) {
      final index = code - firstChar;
      if (index >= 0 && index < widths.length) {
        final value = widths[index];
        // A zero entry inside the range is a real zero-advance glyph only when
        // the font says so; treat it as declared.
        return value;
      }
      return missingWidth;
    }
    return PdfStandardFontMetrics.width(
        _standardName(baseFont), encoding, code);
  }

  /// Strips a subset tag (`ABCDEF+Helvetica`) and any style suffix a standard
  /// metric table would not recognise.
  static String _standardName(String baseFont) {
    var name = baseFont;
    final plus = name.indexOf('+');
    if (plus == 6) name = name.substring(plus + 1);
    return name;
  }
}
