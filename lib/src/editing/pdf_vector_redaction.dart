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
  /// that lie wholly outside byte for byte, clips filled paths that cross an
  /// area's edge, and refuses the document when a *stroked* path crosses one.
  ///
  /// A clipped path is rewritten: Bézier segments are split at the parameters
  /// where they cross an edge, the pieces inside are dropped, and the hole
  /// they leave is closed along the edge in the direction that leaves the
  /// filling rule's verdict — nonzero for `f`, even-odd for `f*` — unchanged
  /// everywhere outside the area. The coordinates that were inside are gone
  /// from the file, not covered up.
  ///
  /// The refusal that is left is about ink, not about geometry. A stroke lays
  /// its pen half a width either side of the path it follows, and 8.4.3.3
  /// lets a projecting cap reach half a width past the ends as well, so
  /// clipping the geometry against the area would still leave the pen showing
  /// inside it. Filling is what carries the artwork in practice, and it is
  /// what this handles; for a stroke, refusing says so out loud instead of
  /// producing a file that looks redacted.
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

  /// The path's own geometry, subpath by subpath, closed as a fill sees it
  /// (8.5.3.1), in the coordinates the content stream wrote.
  final List<_Contour> contours;

  /// The matrix in force, which carries [contours] into the space the
  /// redaction areas are expressed in.
  final _RedactionMatrix matrix;

  /// The painting operator that ended the path object, from 8.5.3.
  final String paint;

  const _PathExtent(this.start, this.end, this.minX, this.minY, this.maxX,
      this.maxY, this.bounded, this.contours, this.matrix, this.paint);

  /// True when the operator strokes, so the ink reaches a pen width either
  /// side of the geometry.
  bool get strokes => _VectorArtScanner._stroking.contains(paint);

  /// True when the operator fills under the even-odd rule (8.5.3.3.3).
  bool get evenOdd => paint == 'f*' || paint == 'B*' || paint == 'b*';

  /// True when the operator paints nothing at all, so the whole object can go
  /// without changing a pixel. `n` only ever survives as the end of a
  /// clipping path, and those are never rewritten.
  bool get paintsNothing => paint == 'n';
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

  /// Path objects that cross an area's edge, each carrying the geometry the
  /// clip needs to cut it down to what is outside.
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

    // The geometry, kept alongside the box so a path that crosses an edge can
    // be clipped instead of refused. A subpath that never moves paints
    // nothing under any filling rule, so it is dropped rather than kept as a
    // contour with no segments.
    final contours = <_Contour>[];
    final pending = <_Segment>[];

    void endSubpath() {
      if (pending.isNotEmpty) {
        final lastX = pending.last.x3, lastY = pending.last.y3;
        if ((lastX - subpathX).abs() > 1e-12 ||
            (lastY - subpathY).abs() > 1e-12) {
          pending.add(_Segment.line(lastX, lastY, subpathX, subpathY));
        }
        contours.add(_Contour(List.of(pending)));
      }
      pending.clear();
    }

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
      contours.clear();
      pending.clear();
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
          contours.clear();
          pending.clear();
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
            if (operator == 'm') {
              endSubpath();
              subpathX = values[0];
              subpathY = values[1];
            } else {
              pending
                  .add(_Segment.line(currentX, currentY, values[0], values[1]));
            }
            currentX = values[0];
            currentY = values[1];
            addPoint(currentX, currentY);
          case 'c':
            if (values == null || values.length != 6) {
              throw FormatException('c takes six coordinates.');
            }
            for (var i = 0; i < 6; i += 2) {
              addPoint(values[i], values[i + 1]);
            }
            pending.add(_Segment.curve(currentX, currentY, values[0], values[1],
                values[2], values[3], values[4], values[5]));
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
            // `v` takes the current point as its first control point and `y`
            // takes the final point as its second (8.5.2.2).
            pending.add(operator == 'v'
                ? _Segment.curve(currentX, currentY, currentX, currentY,
                    values[0], values[1], values[2], values[3])
                : _Segment.curve(currentX, currentY, values[0], values[1],
                    values[2], values[3], values[2], values[3]));
            currentX = values[2];
            currentY = values[3];
          case 'h':
            // Closing ends the subpath; anything that follows without an `m`
            // starts a new one from the same point (8.5.2.1).
            endSubpath();
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
            endSubpath();
            final x = values[0], y = values[1];
            final right = x + values[2], top = y + values[3];
            contours.add(_Contour([
              _Segment.line(x, y, right, y),
              _Segment.line(right, y, right, top),
              _Segment.line(right, top, x, top),
              _Segment.line(x, top, x, y),
            ]));
            currentX = subpathX = x;
            currentY = subpathY = y;
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
          endSubpath();
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
          final extent = _PathExtent(
              pathStart,
              end,
              minX - pad,
              minY - pad,
              maxX + pad,
              maxY + pad,
              bounded,
              List.of(contours),
              matrix,
              operator);
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

/// Replaces the byte ranges of [edits] in [content], in stream order.
///
/// An edit with empty bytes deletes its range, which is how a path object that
/// lies wholly inside an area leaves the file; an edit with bytes puts the
/// clipped path there instead. Everything between edits is copied through
/// untouched, so artwork outside the areas survives byte for byte.
Uint8List _rewritePaths(Uint8List content, List<_ContentReplacement> edits) {
  edits.sort((a, b) => a.start.compareTo(b.start));
  final output = BytesBuilder(copy: false);
  var cursor = 0;
  for (final edit in edits) {
    if (edit.start < cursor) continue;
    output.add(Uint8List.sublistView(content, cursor, edit.start));
    // Operators may have run together, so leave a separator behind.
    output.addByte(10);
    if (edit.bytes.isNotEmpty) {
      output.add(edit.bytes);
      output.addByte(10);
    }
    cursor = edit.end;
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

/// An edit that deletes its byte range rather than replacing it.
final Uint8List _nothing = Uint8List(0);

/// Rewrites one path object that crosses the edge of an area so that nothing
/// it paints, and no coordinate it carries, is inside one.
///
/// Returns null when the crossing turned out to be a false alarm — the box the
/// scanner measured overlaps an area but the geometry inside it does not — in
/// which case the original bytes stay exactly as they are.
_ContentReplacement? _clipCrossingPath(
    _PathExtent path, List<PdfRedactionArea> areas) {
  if (path.strokes) {
    throw UnsupportedError(
        'A stroked path at bytes ${path.start}-${path.end} of the content '
        'stream crosses the edge of a redaction area. Clipping its geometry '
        'would not be enough: a stroke lays ink half a pen width either side '
        'of the path it follows, and 8.4.3.3 lets a cap project half a width '
        'past the ends as well, so the ink reaches past whatever the clip '
        'leaves and the area would still show part of the stroke. Filled '
        'paths that cross an edge are clipped; this refusal is only about the '
        'stroking operators S s B B* b b*. Use PdfVectorArtRedaction.cover to '
        'fall back to an opaque box, which hides the drawing without removing '
        'it, or PdfTextRedaction to rebuild the document from its text alone.');
  }
  // `n` outside a clipping path paints nothing (8.5.3.1), and a matrix with no
  // inverse collapses the plane onto a line, which fills nothing either. Both
  // can go whole: the coordinates leave the file and not a pixel moves.
  if (path.paintsNothing) {
    return _ContentReplacement(path.start, path.end, _nothing);
  }
  final matrix = path.matrix;
  final inverse = matrix.inverse();
  if (inverse == null) {
    return _ContentReplacement(path.start, path.end, _nothing);
  }
  final identity = matrix.a == 1 &&
      matrix.b == 0 &&
      matrix.c == 0 &&
      matrix.d == 1 &&
      matrix.e == 0 &&
      matrix.f == 0;
  // The areas are axis-aligned in the stream's own space, not in whatever
  // space the matrix set up, so the clip happens there and the result is
  // carried back. Under the identity matrix — by far the common case — both
  // steps are skipped and the coordinates are the ones the stream wrote.
  final placed = identity
      ? path.contours
      : [for (final contour in path.contours) contour.mapped(matrix)];
  final result = _subtractAreas(placed, areas, path.evenOdd);
  if (!result.changed) return null;
  _verifyOutsideAreas(result.contours, areas, path.start, path.end);
  if (result.contours.isEmpty) {
    return _ContentReplacement(path.start, path.end, _nothing);
  }
  final local = identity
      ? result.contours
      : [for (final contour in result.contours) contour.mapped(inverse)];
  return _ContentReplacement(path.start, path.end,
      Uint8List.fromList(latin1.encode(_writeContours(local, path.paint))));
}

/// Deletes vector artwork from a content stream and from the Form XObjects it
/// invokes, clipping the paths that only partly meet an area.
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
    final edits = <_ContentReplacement>[
      for (final removal in scan.removals)
        _ContentReplacement(removal.start, removal.end, _nothing),
    ];
    for (final crossing in scan.crossings) {
      final clipped = _clipCrossingPath(crossing, areas);
      if (clipped != null) edits.add(clipped);
    }
    final rewritten = edits.isEmpty ? null : _rewritePaths(content, edits);

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

// ---------------------------------------------------------------------------
// Clipping a filled path against a redaction rectangle
// ---------------------------------------------------------------------------

/// One segment of a subpath, always held as a cubic Bézier.
///
/// A straight line is stored as the cubic whose controls sit at the first and
/// second third of the chord. De Casteljau is then exact on it — subdividing a
/// line gives a line — and [isLine] remembers to write `l` back out instead of
/// a `c` nobody would recognise.
class _Segment {
  final double x0, y0, x1, y1, x2, y2, x3, y3;

  /// True when this segment is a straight line, so the rewrite says `l`.
  final bool isLine;

  const _Segment(this.x0, this.y0, this.x1, this.y1, this.x2, this.y2, this.x3,
      this.y3, this.isLine);

  factory _Segment.line(double x0, double y0, double x3, double y3) => _Segment(
      x0,
      y0,
      x0 + (x3 - x0) / 3,
      y0 + (y3 - y0) / 3,
      x0 + (x3 - x0) * 2 / 3,
      y0 + (y3 - y0) * 2 / 3,
      x3,
      y3,
      true);

  const _Segment.curve(
      this.x0, this.y0, this.x1, this.y1, this.x2, this.y2, this.x3, this.y3)
      : isLine = false;

  double get minX => math.min(math.min(x0, x1), math.min(x2, x3));
  double get maxX => math.max(math.max(x0, x1), math.max(x2, x3));
  double get minY => math.min(math.min(y0, y1), math.min(y2, y3));
  double get maxY => math.max(math.max(y0, y1), math.max(y2, y3));

  (double, double) at(double t) {
    final u = 1 - t;
    final a = u * u * u;
    final b = 3 * u * u * t;
    final c = 3 * u * t * t;
    final d = t * t * t;
    return (
      a * x0 + b * x1 + c * x2 + d * x3,
      a * y0 + b * y1 + c * y2 + d * y3
    );
  }

  /// The part of this segment from parameter 0 to [t], by De Casteljau.
  _Segment _leftOf(double t) {
    final ax = x0 + (x1 - x0) * t, ay = y0 + (y1 - y0) * t;
    final bx = x1 + (x2 - x1) * t, by = y1 + (y2 - y1) * t;
    final cx = x2 + (x3 - x2) * t, cy = y2 + (y3 - y2) * t;
    final dx = ax + (bx - ax) * t, dy = ay + (by - ay) * t;
    final ex = bx + (cx - bx) * t, ey = by + (cy - by) * t;
    final fx = dx + (ex - dx) * t, fy = dy + (ey - dy) * t;
    return _Segment(x0, y0, ax, ay, dx, dy, fx, fy, isLine);
  }

  /// The part of this segment from parameter [t] to 1, by De Casteljau.
  _Segment _rightOf(double t) {
    final ax = x0 + (x1 - x0) * t, ay = y0 + (y1 - y0) * t;
    final bx = x1 + (x2 - x1) * t, by = y1 + (y2 - y1) * t;
    final cx = x2 + (x3 - x2) * t, cy = y2 + (y3 - y2) * t;
    final dx = ax + (bx - ax) * t, dy = ay + (by - ay) * t;
    final ex = bx + (cx - bx) * t, ey = by + (cy - by) * t;
    final fx = dx + (ex - dx) * t, fy = dy + (ey - dy) * t;
    return _Segment(fx, fy, ex, ey, cx, cy, x3, y3, isLine);
  }

  /// The part of this segment between [from] and [to], `0 <= from < to <= 1`.
  _Segment between(double from, double to) {
    var piece = this;
    if (to < 1) piece = piece._leftOf(to);
    if (from > 0) piece = piece._rightOf(from / to);
    return piece;
  }

  _Segment mapped(_RedactionMatrix m) {
    final p0 = m.point(x0, y0);
    final p1 = m.point(x1, y1);
    final p2 = m.point(x2, y2);
    final p3 = m.point(x3, y3);
    return _Segment(
        p0.$1, p0.$2, p1.$1, p1.$2, p2.$1, p2.$2, p3.$1, p3.$2, isLine);
  }
}

/// One closed subpath.
///
/// Every subpath is held closed because that is what a fill sees: 8.5.3.1 says
/// `f` closes an open subpath with a straight line before painting it, so the
/// closing line is part of the shape whether or not the stream spells it out.
class _Contour {
  final List<_Segment> segments;

  const _Contour(this.segments);

  double get startX => segments.first.x0;
  double get startY => segments.first.y0;

  /// True when some segment of this contour can reach into [area].
  ///
  /// A Bézier stays inside the convex hull of its control points, so a hull
  /// that misses the rectangle proves the curve misses it too. The test is
  /// segment by segment rather than on the contour's own box, because a shape
  /// drawn around an area — the box overlaps, every edge misses — must come
  /// through uncut: cutting it would show as a seam across solid ink where
  /// nothing needed removing. The test errs towards "meets", never the other
  /// way.
  bool meets(PdfRedactionArea area) {
    for (final segment in segments) {
      if (segment.maxX > area.left &&
          segment.minX < area.right &&
          segment.maxY > area.bottom &&
          segment.minY < area.top) {
        return true;
      }
    }
    return false;
  }

  _Contour mapped(_RedactionMatrix m) =>
      _Contour([for (final segment in segments) segment.mapped(m)]);
}

/// The side of a line a clip keeps: every point where `ax*x + ay*y + c >= 0`.
class _HalfPlane {
  final double ax, ay, c;

  const _HalfPlane(this.ax, this.ay, this.c);

  double at(double x, double y) => ax * x + ay * y + c;
}

double _cubeRoot(double value) => value < 0
    ? -math.pow(-value, 1 / 3).toDouble()
    : math.pow(value, 1 / 3).toDouble();

/// A cubic in Bernstein form, evaluated as written rather than expanded.
double _bernsteinAt(double d0, double d1, double d2, double d3, double t) {
  final u = 1 - t;
  return d0 * u * u * u +
      3 * d1 * u * u * t +
      3 * d2 * u * t * t +
      d3 * t * t * t;
}

double _bernsteinSlope(double d0, double d1, double d2, double d3, double t) {
  final u = 1 - t;
  return 3 * ((d1 - d0) * u * u + 2 * (d2 - d1) * u * t + (d3 - d2) * t * t);
}

/// Every parameter in `(0, 1)` where the cubic with Bernstein coefficients
/// [d0]..[d3] vanishes — that is, where a Bézier segment crosses the line of a
/// half-plane, because a linear functional of a cubic Bézier is itself a cubic
/// whose Bernstein coefficients are that functional at the control points.
///
/// Cardano gives the roots in closed form and Newton then polishes each one.
/// The sweep afterwards is the safety net that makes this usable for
/// redaction: a root the closed form loses to cancellation still shows up as a
/// sign change between samples, and a missed root is ink left inside an area.
/// Roots the closed form finds without a sign change — a curve tangent to the
/// boundary, a double root — survive too, so a tangency splits the segment
/// harmlessly rather than being read as a crossing.
List<double> _bernsteinRoots(double d0, double d1, double d2, double d3) {
  final scale =
      math.max(math.max(d0.abs(), d1.abs()), math.max(d2.abs(), d3.abs()));
  if (scale == 0) return const [];

  final a = d3 - 3 * d2 + 3 * d1 - d0;
  final b = 3 * (d2 - 2 * d1 + d0);
  final c = 3 * (d1 - d0);
  final d = d0;
  final tiny = 1e-12 * scale;

  final found = <double>[];
  void offer(double t) {
    if (t.isNaN || t <= 0 || t >= 1) return;
    var polished = t;
    for (var i = 0; i < 4; i++) {
      final slope = _bernsteinSlope(d0, d1, d2, d3, polished);
      if (slope.abs() < 1e-18) break;
      final step = _bernsteinAt(d0, d1, d2, d3, polished) / slope;
      if (!step.isFinite) break;
      final next = polished - step;
      if (next <= 0 || next >= 1) break;
      polished = next;
      if (step.abs() < 1e-15) break;
    }
    found.add(polished);
  }

  if (a.abs() <= tiny) {
    if (b.abs() <= tiny) {
      if (c.abs() > tiny) offer(-d / c);
    } else {
      final discriminant = c * c - 4 * b * d;
      if (discriminant >= 0) {
        final root = math.sqrt(discriminant);
        final q = -0.5 * (c + (c >= 0 ? root : -root));
        offer(q / b);
        if (q != 0) offer(d / q);
      }
    }
  } else {
    final p = b / a, q = c / a, r = d / a;
    final shift = p / 3;
    // The depressed cubic y^3 + P*y + Q, with t = y - p/3.
    final bigP = q - p * p / 3;
    final bigQ = 2 * p * p * p / 27 - p * q / 3 + r;
    final discriminant = bigQ * bigQ / 4 + bigP * bigP * bigP / 27;
    if (discriminant > 0) {
      final root = math.sqrt(discriminant);
      offer(_cubeRoot(-bigQ / 2 + root) + _cubeRoot(-bigQ / 2 - root) - shift);
    } else if (discriminant == 0) {
      final u = _cubeRoot(-bigQ / 2);
      offer(2 * u - shift);
      offer(-u - shift);
    } else {
      final m = 2 * math.sqrt(-bigP / 3);
      final ratio = (3 * bigQ) / (bigP * m);
      final angle = math.acos(ratio.clamp(-1.0, 1.0)) / 3;
      for (var k = 0; k < 3; k++) {
        offer(m * math.cos(angle - 2 * math.pi * k / 3) - shift);
      }
    }
  }

  // Safety net: a sign change between samples holds a root whether or not the
  // closed form reported it.
  const samples = 32;
  var previous = _bernsteinAt(d0, d1, d2, d3, 0);
  for (var i = 1; i <= samples; i++) {
    final t = i / samples;
    final value = _bernsteinAt(d0, d1, d2, d3, t);
    if (previous != 0 &&
        value != 0 &&
        (previous < 0) != (value < 0) &&
        !found.any((root) => root > t - 1 / samples && root < t)) {
      var low = (i - 1) / samples, high = t;
      var lowValue = previous;
      for (var step = 0; step < 60; step++) {
        final middle = (low + high) / 2;
        if (middle <= low || middle >= high) break;
        final middleValue = _bernsteinAt(d0, d1, d2, d3, middle);
        if (middleValue == 0) {
          low = high = middle;
          break;
        }
        if ((lowValue < 0) != (middleValue < 0)) {
          high = middle;
        } else {
          low = middle;
          lowValue = middleValue;
        }
      }
      final root = (low + high) / 2;
      if (root > 0 && root < 1) found.add(root);
    }
    previous = value;
  }

  found.sort();
  final roots = <double>[];
  for (final root in found) {
    if (roots.isEmpty || root - roots.last > 1e-9) roots.add(root);
  }
  return roots;
}

/// Appends [piece] to [out], bridging any gap along the clip boundary.
///
/// The gap is where the contour left the half-plane and came back; both ends
/// sit on the boundary line, so the bridge sits on it too and adds nothing to
/// the winding number of any point strictly inside.
void _appendPiece(List<_Segment> out, _Segment piece) {
  if (out.isNotEmpty) {
    final lastX = out.last.x3, lastY = out.last.y3;
    if ((lastX - piece.x0).abs() > 1e-9 || (lastY - piece.y0).abs() > 1e-9) {
      out.add(_Segment.line(lastX, lastY, piece.x0, piece.y0));
    }
  }
  out.add(piece);
}

/// Sutherland–Hodgman against one half-plane, with Bézier segments split at
/// the parameters where they cross the boundary.
///
/// The result is one closed contour whose winding number, at every point
/// strictly inside the half-plane, equals the winding number of [contour]
/// there. That is the whole reason this is safe for both filling rules: the
/// discarded arc and the bridge that replaces it both lie in the closed
/// half-plane on the other side, which is simply connected and misses the
/// point, so the two are homotopic there and make the same turn around it.
/// `f` reads that number against zero and `f*` against its parity (8.5.3.3.2,
/// 8.5.3.3.3), so both verdicts survive.
_Contour? _clipToHalfPlane(_Contour contour, _HalfPlane plane) {
  final out = <_Segment>[];
  for (final segment in contour.segments) {
    final d0 = plane.at(segment.x0, segment.y0);
    final d1 = plane.at(segment.x1, segment.y1);
    final d2 = plane.at(segment.x2, segment.y2);
    final d3 = plane.at(segment.x3, segment.y3);
    // A Bézier stays within the convex hull of its control points, so these
    // two tests are exact rather than approximate.
    if (d0 >= 0 && d1 >= 0 && d2 >= 0 && d3 >= 0) {
      _appendPiece(out, segment);
      continue;
    }
    if (d0 <= 0 && d1 <= 0 && d2 <= 0 && d3 <= 0) continue;
    final cuts = <double>[0, ..._bernsteinRoots(d0, d1, d2, d3), 1];
    for (var i = 0; i + 1 < cuts.length; i++) {
      final from = cuts[i], to = cuts[i + 1];
      if (to - from < 1e-12) continue;
      final middle = segment.at((from + to) / 2);
      // A piece sitting on the boundary is dropped rather than kept: it
      // encloses no area, and erring towards dropping errs towards taking ink
      // out of the area rather than leaving it behind.
      if (plane.at(middle.$1, middle.$2) <= 0) continue;
      _appendPiece(out, segment.between(from, to));
    }
  }
  if (out.isEmpty) return null;
  final startX = out.first.x0, startY = out.first.y0;
  final endX = out.last.x3, endY = out.last.y3;
  if ((startX - endX).abs() > 1e-9 || (startY - endY).abs() > 1e-9) {
    out.add(_Segment.line(endX, endY, startX, startY));
  }
  return _Contour(out);
}

/// The winding number of [contours] at ([px], [py]), positive counterclockwise.
///
/// Curves are walked as chords, which is enough because this is only ever
/// asked about the centre of a redaction area and only ever about contours
/// that provably miss that area: the point is far from every edge, so no
/// amount of flattening error can change the count.
int _windingAt(List<_Contour> contours, double px, double py) {
  var winding = 0;
  for (final contour in contours) {
    for (final segment in contour.segments) {
      final steps = segment.isLine ? 1 : 24;
      var ax = segment.x0, ay = segment.y0;
      for (var i = 1; i <= steps; i++) {
        final double bx, by;
        if (i == steps) {
          bx = segment.x3;
          by = segment.y3;
        } else {
          final point = segment.at(i / steps);
          bx = point.$1;
          by = point.$2;
        }
        final side = (bx - ax) * (py - ay) - (px - ax) * (by - ay);
        if (ay <= py) {
          if (by > py && side > 0) winding++;
        } else if (by <= py && side < 0) {
          winding--;
        }
        ax = bx;
        ay = by;
      }
    }
  }
  return winding;
}

/// The rectangle of [area] as one closed contour.
_Contour _areaContour(PdfRedactionArea area, {required bool clockwise}) {
  final corners = clockwise
      ? [
          (area.left, area.bottom),
          (area.left, area.top),
          (area.right, area.top),
          (area.right, area.bottom)
        ]
      : [
          (area.left, area.bottom),
          (area.right, area.bottom),
          (area.right, area.top),
          (area.left, area.top)
        ];
  return _Contour([
    for (var i = 0; i < 4; i++)
      _Segment.line(corners[i].$1, corners[i].$2, corners[(i + 1) % 4].$1,
          corners[(i + 1) % 4].$2)
  ]);
}

/// What [_subtractAreas] made of a path.
class _AreaSubtraction {
  final List<_Contour> contours;

  /// False when no area touched anything the path paints, so the original
  /// bytes can stay exactly as they are.
  final bool changed;

  const _AreaSubtraction(this.contours, this.changed);
}

/// Removes [areas] from the region [contours] fills, leaving the filling
/// rule's verdict outside the areas exactly as it was.
///
/// The complement of a rectangle is not convex, which is what makes this
/// awkward; it is however the union of four convex pieces — west `x <= left`,
/// east `x >= right`, and the two ends of the strip between them, `y <= bottom`
/// and `y >= top`. Clipping a contour to each of them preserves its winding
/// number there, and a contour that ends up inside one convex piece winds zero
/// times around every point outside that piece, so the four results simply add
/// up: the original winding everywhere outside the rectangle, and zero inside.
///
/// Contours that never reach the rectangle are not cut at all. They keep their
/// exact geometry, which is what keeps the rendering outside an area
/// unchanged, and the turns they make around the area — a shape with the area
/// in the middle of it — are cancelled by rectangles of the opposite
/// orientation instead. That is the case where cutting would have shown as a
/// seam down the middle of a solid shape.
_AreaSubtraction _subtractAreas(
    List<_Contour> contours, List<PdfRedactionArea> areas, bool evenOdd) {
  var current = contours;
  var changed = false;
  for (final area in areas) {
    final clear = <_Contour>[];
    final meets = <_Contour>[];
    for (final contour in current) {
      (contour.meets(area) ? meets : clear).add(contour);
    }
    final coverage = _windingAt(
        clear, (area.left + area.right) / 2, (area.bottom + area.top) / 2);
    final covered = evenOdd ? coverage.isOdd : coverage != 0;
    if (meets.isEmpty && !covered) continue;
    if (coverage.abs() > 16) {
      throw UnsupportedError(
          'A path winds ${coverage.abs()} times around a redaction area, more '
          'than vector redaction is willing to cancel out. Use '
          'PdfVectorArtRedaction.cover to fall back to an opaque box.');
    }
    changed = true;

    final next = <_Contour>[...clear];
    for (final contour in meets) {
      final west = _clipToHalfPlane(contour, _HalfPlane(-1, 0, area.left));
      if (west != null) next.add(west);
      final east = _clipToHalfPlane(contour, _HalfPlane(1, 0, -area.right));
      if (east != null) next.add(east);
      var strip = _clipToHalfPlane(contour, _HalfPlane(1, 0, -area.left));
      if (strip != null) {
        strip = _clipToHalfPlane(strip, _HalfPlane(-1, 0, area.right));
      }
      if (strip != null) {
        final south = _clipToHalfPlane(strip, _HalfPlane(0, -1, area.bottom));
        if (south != null) next.add(south);
        final north = _clipToHalfPlane(strip, _HalfPlane(0, 1, -area.top));
        if (north != null) next.add(north);
      }
    }

    if (covered) {
      final copies = evenOdd ? 1 : coverage.abs();
      for (var i = 0; i < copies; i++) {
        next.add(_areaContour(area, clockwise: coverage > 0));
      }
    }
    current = next;
  }
  return _AreaSubtraction(current, changed);
}

/// Refuses rather than writing a path that still reaches into an area.
///
/// The clip is meant to be exact and every case it is known to get wrong is
/// refused before reaching here. This is the check that the reasoning held: it
/// samples the geometry about to be written and, if one point of it lies
/// inside an area, throws instead of producing a file that looks redacted.
void _verifyOutsideAreas(
    List<_Contour> contours, List<PdfRedactionArea> areas, int start, int end) {
  const tolerance = 1e-4;
  for (final contour in contours) {
    for (final segment in contour.segments) {
      final steps = segment.isLine ? 8 : 32;
      for (var i = 0; i <= steps; i++) {
        final point = segment.at(i / steps);
        for (final area in areas) {
          if (point.$1 > area.left + tolerance &&
              point.$1 < area.right - tolerance &&
              point.$2 > area.bottom + tolerance &&
              point.$2 < area.top - tolerance) {
            throw UnsupportedError(
                'Clipping the path at bytes $start-$end of the content stream '
                'against the redaction areas left geometry at '
                '(${point.$1}, ${point.$2}), which is inside an area. That is '
                'a bug in the clip, and refusing is the only honest answer: a '
                'file that looks redacted while still holding the coordinates '
                'is worse than one that was never written. Use '
                'PdfVectorArtRedaction.cover to fall back to an opaque box.');
          }
        }
      }
    }
  }
}

/// A PDF real with six decimals — a millionth of a point, far below what any
/// rasteriser resolves — and no exponent, which the syntax of 7.3.3 forbids.
String _clipNumber(double value) {
  if (!value.isFinite) {
    throw UnsupportedError('Clipping produced a non-finite coordinate.');
  }
  if (value.abs() >= 1e15) return _pdfNumber(value);
  var text = value.toStringAsFixed(6);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  return text == '-0' ? '0' : text;
}

/// Writes [contours] back as a path object painted by [paint].
String _writeContours(List<_Contour> contours, String paint) {
  final buffer = StringBuffer();
  for (final contour in contours) {
    buffer.writeln(
        '${_clipNumber(contour.startX)} ${_clipNumber(contour.startY)} m');
    final segments = contour.segments;
    var count = segments.length;
    final last = segments.last;
    // The closing line is what `h` means, so say `h` rather than both.
    if (count > 1 &&
        last.isLine &&
        (last.x3 - contour.startX).abs() < 1e-9 &&
        (last.y3 - contour.startY).abs() < 1e-9) {
      count--;
    }
    for (var i = 0; i < count; i++) {
      final segment = segments[i];
      if (segment.isLine) {
        buffer
            .writeln('${_clipNumber(segment.x3)} ${_clipNumber(segment.y3)} l');
      } else {
        buffer.writeln('${_clipNumber(segment.x1)} ${_clipNumber(segment.y1)} '
            '${_clipNumber(segment.x2)} ${_clipNumber(segment.y2)} '
            '${_clipNumber(segment.x3)} ${_clipNumber(segment.y3)} c');
      }
    }
    buffer.writeln('h');
  }
  buffer.writeln(paint);
  return buffer.toString();
}
