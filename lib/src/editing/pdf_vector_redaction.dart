part of 'pdf_text_extraction.dart';

/// What [PdfAreaRedaction] does with vector artwork that meets an area.
///
/// Painting an opaque box over a path hides nothing: the coordinates stay in
/// the content stream, and deleting the box brings the drawing back. Only
/// deleting the path object removes the data.
enum PdfVectorArtRedaction {
  /// Leaves every path where it is and relies on the overlay to hide it.
  ///
  /// This is not redaction. It exists for callers who want the previous,
  /// cover-only behaviour and know what they are buying.
  cover,

  /// Deletes path objects that lie wholly inside an area, keeps path objects
  /// that lie wholly outside byte for byte, and refuses the document when a
  /// path crosses an area's edge.
  ///
  /// The refusal is deliberate. Clipping a path made of Bézier segments
  /// against a rectangle means splitting curves and rebuilding the winding,
  /// and a wrong split leaves ink — or data — behind while the file looks
  /// redacted. Refusing says so out loud instead.
  removeOrReject,
}

/// The line-width state a `gs` operator can install, read ahead of the scan so
/// that classifying a stroke stays synchronous.
class _ExtGStateWidths {
  final Map<String, double?> lineWidth;
  final Map<String, double?> miterLimit;
  final Set<String> known;

  const _ExtGStateWidths(this.lineWidth, this.miterLimit, this.known);

  static const _ExtGStateWidths empty = _ExtGStateWidths({}, {}, <String>{});

  static Future<_ExtGStateWidths> resolve(PdfDictionary? resources) async {
    final states = await resources?.dictionaryEntry(PdfName('ExtGState'));
    if (states == null) return empty;
    final widths = <String, double?>{};
    final miters = <String, double?>{};
    final known = <String>{};
    for (final key in states.keySet()) {
      final state = await states.dictionaryEntry(key);
      if (state == null) continue;
      known.add(key.getValue());
      widths[key.getValue()] = await state.decimalEntry(PdfName('LW'));
      miters[key.getValue()] = await state.decimalEntry(PdfName('ML'));
    }
    return _ExtGStateWidths(widths, miters, known);
  }
}

/// One path object found in a content stream, already reduced to the page-space
/// box its ink can occupy.
class _PathExtent {
  final int start, end;
  final double minX, minY, maxX, maxY;

  /// False when the pen width could not be bounded, which makes a stroke's
  /// real extent unknown.
  final bool bounded;

  const _PathExtent(this.start, this.end, this.minX, this.minY, this.maxX,
      this.maxY, this.bounded);
}

/// A `Do` invocation, kept with the matrix in force so the caller can map the
/// areas into the invoked object's own space.
class _VectorFormUse {
  final String name;
  final _RedactionMatrix matrix;

  const _VectorFormUse(this.name, this.matrix);
}

class _VectorArtScan {
  /// Path objects to delete, in stream order.
  final List<_PathExtent> removals;

  /// Path objects that cross an area's edge; a non-empty list means the
  /// document cannot be rewritten safely.
  final List<_PathExtent> crossings;

  final List<_VectorFormUse> forms;

  const _VectorArtScan(this.removals, this.crossings, this.forms);
}

/// Finds the path objects of one content stream and places each of them
/// inside, outside or across the redaction areas.
///
/// ISO 32000-1 8.5.2 (path construction: `m l c v y h re`) and 8.5.3 (path
/// painting: `S s f F f* B B* b b* n`) define the unit this works on: a path
/// object runs from its first construction operator to its painting operator
/// and nothing may interrupt it, so its byte range can be cut out whole.
///
/// A path's extent is the bounding box of its points in page space. Bézier
/// control points are included rather than the curve they describe, which
/// overstates the box and never understates it. A stroked path adds half the
/// pen width times the miter limit, which bounds both the miter spikes of
/// 8.4.3.5 and the projecting caps of 8.4.3.3.
class _VectorArtScanner {
  final Uint8List content;
  final List<PdfRedactionArea> areas;
  final _ExtGStateWidths states;

  _VectorArtScanner(this.content, this.areas, this.states);

  static const _construction = {'m', 'l', 'c', 'v', 'y', 'h', 're'};
  static const _painting = {
    'S',
    's',
    'f',
    'F',
    'f*',
    'B',
    'B*',
    'b',
    'b*',
    'n'
  };
  static const _stroking = {'S', 's', 'B', 'B*', 'b', 'b*'};

  _VectorArtScan run() {
    final lexer = _ContentTokens(content, allowDictionaries: true);
    final removals = <_PathExtent>[];
    final crossings = <_PathExtent>[];
    final forms = <_VectorFormUse>[];
    final operands = <Object>[];
    var groupStart = 0;

    var matrix = const _RedactionMatrix(1, 0, 0, 1, 0, 0);
    var width = 1.0, miter = 10.0;
    var widthKnown = true;
    final stack = <(_RedactionMatrix, double, double, bool)>[];

    var inPath = false, clipping = false, empty = true;
    // A miter spike only exists where two segments meet, so a path with a
    // single open segment is padded by its cap alone.
    var joins = false, segments = 0;
    var pathStart = 0;
    var minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0;
    var currentX = 0.0, currentY = 0.0, subpathX = 0.0, subpathY = 0.0;

    void addPoint(double x, double y) {
      final point = matrix.point(x, y);
      if (empty) {
        minX = maxX = point.$1;
        minY = maxY = point.$2;
        empty = false;
        return;
      }
      minX = math.min(minX, point.$1);
      maxX = math.max(maxX, point.$1);
      minY = math.min(minY, point.$2);
      maxY = math.max(maxY, point.$2);
    }

    void reset() {
      inPath = false;
      clipping = false;
      empty = true;
      joins = false;
      segments = 0;
    }

    while (!lexer.done) {
      final before = lexer.position;
      final token = lexer.next();
      if (token == null) break;
      if (token is! _Operator) {
        if (operands.isEmpty) groupStart = before;
        operands.add(token);
        continue;
      }
      final start = operands.isEmpty ? before : groupStart;
      final end = lexer.position;
      final operator = token.value;
      final values = _numbers(operands);

      if (_construction.contains(operator)) {
        if (!inPath) {
          inPath = true;
          clipping = false;
          empty = true;
          joins = false;
          segments = 0;
          pathStart = start;
        }
        if (const {'l', 'c', 'v', 'y'}.contains(operator) && ++segments > 1) {
          joins = true;
        }
        if (operator == 'h' || operator == 're') joins = true;
        switch (operator) {
          case 'm':
          case 'l':
            if (values == null || values.length != 2) {
              throw FormatException('$operator takes two coordinates.');
            }
            currentX = values[0];
            currentY = values[1];
            if (operator == 'm') {
              subpathX = currentX;
              subpathY = currentY;
            }
            addPoint(currentX, currentY);
          case 'c':
            if (values == null || values.length != 6) {
              throw FormatException('c takes six coordinates.');
            }
            for (var i = 0; i < 6; i += 2) {
              addPoint(values[i], values[i + 1]);
            }
            currentX = values[4];
            currentY = values[5];
          case 'v':
          case 'y':
            if (values == null || values.length != 4) {
              throw FormatException('$operator takes four coordinates.');
            }
            addPoint(currentX, currentY);
            addPoint(values[0], values[1]);
            addPoint(values[2], values[3]);
            currentX = values[2];
            currentY = values[3];
          case 'h':
            currentX = subpathX;
            currentY = subpathY;
          case 're':
            if (values == null || values.length != 4) {
              throw FormatException('re takes four numbers.');
            }
            addPoint(values[0], values[1]);
            addPoint(values[0] + values[2], values[1]);
            addPoint(values[0], values[1] + values[3]);
            addPoint(values[0] + values[2], values[1] + values[3]);
            currentX = subpathX = values[0];
            currentY = subpathY = values[1];
        }
        operands.clear();
        continue;
      }

      if (operator == 'W' || operator == 'W*') {
        clipping = true;
        operands.clear();
        continue;
      }

      if (_painting.contains(operator)) {
        if (inPath && !clipping && !empty) {
          final strokes = _stroking.contains(operator);
          var bounded = true;
          var pad = 0.0;
          if (strokes) {
            if (!widthKnown) {
              bounded = false;
            } else {
              // The pen is round in user space; the matrix can stretch it, and
              // the Frobenius norm bounds how far any unit vector can travel.
              final scale = math.sqrt(matrix.a * matrix.a +
                  matrix.b * matrix.b +
                  matrix.c * matrix.c +
                  matrix.d * matrix.d);
              pad = width / 2 * (joins ? math.max(miter, 1) : 1) * scale;
            }
          }
          final extent = _PathExtent(pathStart, end, minX - pad, minY - pad,
              maxX + pad, maxY + pad, bounded);
          final placement = _classify(extent);
          if (placement == _Placement.inside) {
            removals.add(extent);
          } else if (placement == _Placement.crossing) {
            crossings.add(extent);
          }
        }
        reset();
        operands.clear();
        continue;
      }

      switch (operator) {
        case 'q':
          stack.add((matrix, width, miter, widthKnown));
        case 'Q':
          if (stack.isNotEmpty) {
            final saved = stack.removeLast();
            matrix = saved.$1;
            width = saved.$2;
            miter = saved.$3;
            widthKnown = saved.$4;
          }
        case 'cm':
          if (values != null && values.length == 6) {
            matrix = _RedactionMatrix.from(values).multiply(matrix);
          }
        case 'w':
          if (values != null && values.length == 1) {
            width = values[0];
            widthKnown = true;
          } else {
            widthKnown = false;
          }
        case 'M':
          if (values != null && values.length == 1) {
            miter = values[0];
          } else {
            widthKnown = false;
          }
        case 'gs':
          final name = operands.length == 1 && operands.first is _Name
              ? (operands.first as _Name).value
              : null;
          if (name == null || !states.known.contains(name)) {
            // An unresolvable graphics state can carry any pen width.
            widthKnown = false;
          } else {
            final lw = states.lineWidth[name];
            if (lw != null) width = lw;
            final ml = states.miterLimit[name];
            if (ml != null) miter = ml;
          }
        case 'Do':
          if (operands.length == 1 && operands.first is _Name) {
            forms.add(_VectorFormUse((operands.first as _Name).value, matrix));
          }
        case 'BI':
          lexer.readInlineImage();
      }
      operands.clear();
    }
    return _VectorArtScan(removals, crossings, forms);
  }

  _Placement _classify(_PathExtent extent) {
    for (final area in areas) {
      if (extent.bounded &&
          extent.minX >= area.left &&
          extent.maxX <= area.right &&
          extent.minY >= area.bottom &&
          extent.maxY <= area.top) {
        return _Placement.inside;
      }
    }
    for (final area in areas) {
      if (extent.maxX > area.left &&
          extent.minX < area.right &&
          extent.maxY > area.bottom &&
          extent.minY < area.top) {
        return _Placement.crossing;
      }
    }
    return _Placement.outside;
  }

  static List<double>? _numbers(List<Object> operands) {
    final result = <double>[];
    for (final operand in operands) {
      if (operand is! num) return null;
      result.add(operand.toDouble());
    }
    return result;
  }
}

enum _Placement { inside, outside, crossing }

/// Cuts the byte ranges of [removals] out of [content].
Uint8List _withoutPaths(Uint8List content, List<_PathExtent> removals) {
  final output = BytesBuilder(copy: false);
  var cursor = 0;
  for (final removal in removals) {
    if (removal.start < cursor) continue;
    output.add(Uint8List.sublistView(content, cursor, removal.start));
    // Operators may have run together, so leave a separator behind.
    output.addByte(10);
    cursor = removal.end;
  }
  output.add(Uint8List.sublistView(content, cursor));
  return output.takeBytes();
}

/// What a rewrite produced for one content stream.
class _VectorRewrite {
  /// New bytes for the stream, or null when nothing in it changed.
  final Uint8List? content;

  /// A replacement resources dictionary, present only when a nested Form
  /// XObject was rewritten and has to be swapped in without touching the
  /// dictionary the rest of the document shares.
  final PdfDictionary? resources;

  const _VectorRewrite(this.content, this.resources);

  bool get changed => content != null || resources != null;
}

/// Deletes vector artwork from a content stream and from the Form XObjects it
/// invokes, or refuses the document.
abstract final class _VectorArtRedactor {
  static Future<_VectorRewrite> apply(
      PdfDocument document,
      PdfDictionary? resources,
      Uint8List content,
      List<PdfRedactionArea> areas,
      int depth) async {
    if (depth > 16) {
      throw UnsupportedError(
          'Form XObjects nest too deeply for vector redaction.');
    }
    if (content.isEmpty) return const _VectorRewrite(null, null);
    final scan = _VectorArtScanner(
            content, areas, await _ExtGStateWidths.resolve(resources))
        .run();
    if (scan.crossings.isNotEmpty) {
      final first = scan.crossings.first;
      throw UnsupportedError(
          'A path at bytes ${first.start}-${first.end} of the content stream '
          'crosses the edge of a redaction area, and area redaction does not '
          'clip vector geometry: cutting a Bézier path against a rectangle '
          'would have to split curves and rebuild the winding, and a file that '
          'looks redacted but still holds the coordinates is worse than a '
          'refusal. Use PdfVectorArtRedaction.cover to fall back to an opaque '
          'box, which hides the drawing without removing it, or PdfTextRedaction '
          'to rebuild the document from its text alone.');
    }
    final rewritten =
        scan.removals.isEmpty ? null : _withoutPaths(content, scan.removals);

    if (scan.forms.isEmpty || resources == null) {
      return _VectorRewrite(rewritten, null);
    }
    final xObjects = await resources.dictionaryEntry(PdfName.xObject);
    if (xObjects == null) return _VectorRewrite(rewritten, null);

    final byName = <String, List<PdfRedactionArea>>{};
    for (final use in scan.forms) {
      final stream = await xObjects.streamEntry(PdfName(use.name));
      if (stream == null) continue;
      if ((await stream.nameEntry(PdfName.subtype))?.getValue() != 'Form') {
        continue;
      }
      var formToOuter = use.matrix;
      final own = await stream.arrayEntry(PdfName.matrix);
      if (own != null && own.size() == 6) {
        formToOuter = _RedactionMatrix.from(await own.toDoubleArray())
            .multiply(formToOuter);
      }
      final inverse = formToOuter.inverse();
      if (inverse == null) continue;
      final mapped = byName.putIfAbsent(use.name, () => []);
      for (final area in areas) {
        mapped.add(PdfAreaRedaction._transformArea(area, inverse));
      }
    }

    PdfDictionary? replacementXObjects;
    for (final entry in byName.entries) {
      final stream = await xObjects.streamEntry(PdfName(entry.key));
      if (stream == null) continue;
      final formContent = await stream.getBytes();
      if (formContent == null) continue;
      final formResources =
          await stream.dictionaryEntry(PdfName.resources) ?? resources;
      final result = await apply(
          document, formResources, formContent, entry.value, depth + 1);
      if (!result.changed) continue;
      final clone = await PdfAreaRedaction._cloneDecodedStream(
          stream, result.content ?? formContent);
      if (result.resources != null) {
        clone.put(PdfName.resources, result.resources!);
      }
      clone.attachToDocument(document);
      replacementXObjects ??= PdfDictionary.fromDictionary(xObjects);
      replacementXObjects.put(PdfName(entry.key), clone.indirectHandle()!);
    }
    if (replacementXObjects == null) return _VectorRewrite(rewritten, null);
    final replacement = PdfDictionary.fromDictionary(resources)
      ..put(PdfName.xObject, replacementXObjects);
    return _VectorRewrite(rewritten, replacement);
  }
}
