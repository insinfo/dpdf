import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dgfx/dgfx.dart';

import '../kernel/geom/rectangle.dart';
import '../kernel/pdf/colorspace/pdf_color_space.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_page.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/function/pdf_function.dart';
import '../io/image/png_encoder.dart';
import 'content_parser.dart';
import 'glyph_source.dart';
import 'image_decoder.dart';

/// How a page is turned into pixels.
class PdfRenderOptions {
  /// Output resolution. A PDF user unit is 1/72 inch, so 72 renders the page
  /// at one pixel per point and 300 gives a print-resolution raster.
  final double dpi;

  /// Colour painted before anything else, as `0xAARRGGBB`. Opaque white is
  /// what a viewer shows, and what makes a PNG look like the printed page.
  final int background;

  /// Honour the page's `/Rotate` entry.
  final bool applyRotation;

  /// Largest surface the renderer will allocate, in pixels. A page whose
  /// media box or dpi would exceed it is refused rather than exhausting
  /// memory.
  final int maxPixels;

  const PdfRenderOptions({
    this.dpi = 150,
    this.background = 0xFFFFFFFF,
    this.applyRotation = true,
    this.maxPixels = 64 * 1000 * 1000,
    this.fontFallback,
  });

  /// Supplies a typeface for text whose font the PDF does not embed.
  ///
  /// Most real documents reference at least one font without carrying it —
  /// the standard fourteen, or whatever the producer assumed the reader has.
  /// Without this, that text is measured and positioned but not drawn, and
  /// the report says so. This package bundles no typefaces on purpose: which
  /// font to substitute, and under which licence, is the caller's decision.
  ///
  /// ```dart
  /// PdfRenderOptions(fontFallback: (request) async =>
  ///     File(request.isSerif ? 'serif.ttf' : 'sans.ttf').readAsBytes());
  /// ```
  final PdfFontFallback? fontFallback;
}

/// What the renderer could not draw.
///
/// A page renders as far as it can and reports the rest, because a single
/// unsupported construct should not cost the whole page.
class PdfRenderReport {
  /// Operators encountered that this renderer does not implement, with how
  /// many times each appeared.
  final Map<String, int> unsupportedOperators;

  /// Text-showing operators skipped because no glyph outlines were available.
  final int glyphsSkipped;

  /// Images that could not be decoded.
  final int imagesSkipped;

  /// Why each font that could not be drawn was rejected, by resource name.
  ///
  /// Counting skipped text is enough to know a page is incomplete, but not to
  /// do anything about it. This says whether the font simply carries no
  /// program, or carries one this cannot read, or uses an encoding this
  /// refuses to guess at.
  final Map<String, PdfGlyphFailure> fontFailures;

  const PdfRenderReport({
    required this.unsupportedOperators,
    required this.glyphsSkipped,
    required this.imagesSkipped,
    this.fontFailures = const {},
  });

  bool get isComplete =>
      unsupportedOperators.isEmpty && glyphsSkipped == 0 && imagesSkipped == 0;

  @override
  String toString() => 'PdfRenderReport('
      '${isComplete ? 'complete' : 'partial'}'
      '${unsupportedOperators.isEmpty ? '' : ', unsupported: '
          '${unsupportedOperators.keys.join(' ')}'}'
      '${glyphsSkipped == 0 ? '' : ', $glyphsSkipped text op(s) skipped'}'
      '${imagesSkipped == 0 ? '' : ', $imagesSkipped image(s) skipped'})';
}

/// A rendered page.
class PdfRenderedPage {
  final int width;
  final int height;

  /// Straight-alpha `0xAARRGGBB`, one word per pixel, row major.
  final Uint32List pixels;

  final PdfRenderReport report;

  const PdfRenderedPage({
    required this.width,
    required this.height,
    required this.pixels,
    required this.report,
  });

  /// Encodes the surface as a PNG.
  Uint8List toPng({bool opaque = true}) => PngEncoder.encodeArgb32(
        pixels,
        width: width,
        height: height,
        opaque: opaque,
      );
}

/// Draws a PDF page onto a pixel surface.
///
/// The renderer interprets the page's content stream and hands geometry to a
/// rasterizer. Coordinates are transformed into device space **before** a path
/// is built, because the rasterizer flattens curves when they are added: at
/// 300 dpi a curve flattened in user space would show its facets.
///
/// What it draws today: paths (fill, stroke, both, with either winding rule),
/// clipping, the device and CIE colour spaces including Indexed, Separation
/// and DeviceN, coloured tiling patterns, alpha/luminosity soft masks, image
/// XObjects with their masks, inline images, form XObjects recursively, and
/// text as real glyph outlines.
///
/// Text is drawn when the PDF embeds the font program. A document that
/// references a font without carrying it — the standard fourteen, most often —
/// has that text measured and positioned but not drawn, and
/// [PdfRenderReport.fontFailures] says why. Supply
/// [PdfRenderOptions.fontFallback] to have it drawn with a typeface of your
/// choosing.
class PdfPageRenderer {
  PdfPageRenderer._();

  /// Renders [page].
  static Future<PdfRenderedPage> render(
    PdfPage page, {
    PdfRenderOptions options = const PdfRenderOptions(),
  }) async {
    final box = await _pageBox(page);
    final scale = options.dpi / 72.0;
    var rotation = 0;
    if (options.applyRotation) {
      rotation = ((await page.rotationDegrees()) % 360 + 360) % 360;
      rotation -= rotation % 90;
    }

    final boxWidth = box.getWidth() * scale;
    final boxHeight = box.getHeight() * scale;
    final swapped = rotation == 90 || rotation == 270;
    final width = math.max(1, (swapped ? boxHeight : boxWidth).round());
    final height = math.max(1, (swapped ? boxWidth : boxHeight).round());
    if (width * height > options.maxPixels) {
      throw ArgumentError('Rendering this page at ${options.dpi} dpi needs '
          '${width * height} pixels, past the ${options.maxPixels} limit.');
    }

    final image = BLImage(width, height)..clear(options.background);
    final context = BLContext(image);

    // PDF user space is y-up with the origin at the media box's lower left;
    // a raster is y-down from its top left. This is that flip, plus the dpi
    // scale, plus whatever /Rotate asks for.
    var base = BLMatrix2D(
      scale,
      0,
      0,
      -scale,
      -box.getX() * scale,
      box.getTop() * scale,
    );
    base = switch (rotation) {
      90 => base.multiply(BLMatrix2D(0, 1, -1, 0, boxHeight, 0)),
      180 => base.multiply(BLMatrix2D(-1, 0, 0, -1, boxWidth, boxHeight)),
      270 => base.multiply(BLMatrix2D(0, -1, 1, 0, 0, boxWidth)),
      _ => base,
    };

    final renderer =
        _Renderer(context, base, fontFallback: options.fontFallback);
    final resources =
        await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
    await renderer.run(await page.contentPayload(), resources, 0);
    context.flush();

    return PdfRenderedPage(
      width: width,
      height: height,
      pixels: image.pixels,
      report: PdfRenderReport(
        unsupportedOperators: Map.unmodifiable(renderer.unsupported),
        glyphsSkipped: renderer.glyphsSkipped,
        imagesSkipped: renderer.imagesSkipped,
        fontFailures: Map.unmodifiable(renderer.fontFailures),
      ),
    );
  }

  /// Renders [page] straight to PNG bytes.
  static Future<Uint8List> renderToPng(
    PdfPage page, {
    PdfRenderOptions options = const PdfRenderOptions(),
  }) async {
    return (await render(page, options: options)).toPng();
  }

  /// The crop box when there is one, else the media box, else US Letter.
  static Future<Rectangle> _pageBox(PdfPage page) async {
    try {
      final crop = await page.cropBounds();
      if (crop.getWidth() > 0 && crop.getHeight() > 0) return crop;
    } on Object {
      // A missing or malformed CropBox falls back to the media box.
    }
    try {
      final media = await page.mediaBounds();
      if (media.getWidth() > 0 && media.getHeight() > 0) return media;
    } on Object {
      // Fall through to the default below.
    }
    return Rectangle(0, 0, 612, 792);
  }
}

/// The PDF graphics state the renderer tracks.
///
/// Only what affects drawing: the rasterizer owns the clip, so the clip lives
/// on its stack rather than here.
class _State {
  BLMatrix2D ctm;
  int fillColour;
  int strokeColour;
  PdfColorSpace? fillSpace;
  PdfColorSpace? strokeSpace;
  double lineWidth;
  BLStrokeCap lineCap;
  BLStrokeJoin lineJoin;
  double miterLimit;
  List<double> dashArray;
  double dashPhase;
  double fillAlpha;
  double strokeAlpha;
  PdfDictionary? fillPattern;
  PdfDictionary? strokePattern;

  // Text state.
  double fontSize;
  double charSpacing;
  double wordSpacing;
  double horizontalScale;
  double leading;
  double rise;
  int renderMode;

  _State({
    required this.ctm,
    this.fillColour = 0xFF000000,
    this.strokeColour = 0xFF000000,
    this.fillSpace,
    this.strokeSpace,
    this.lineWidth = 1,
    this.lineCap = BLStrokeCap.butt,
    this.lineJoin = BLStrokeJoin.miterBevel,
    this.miterLimit = 10,
    this.dashArray = const [],
    this.dashPhase = 0,
    this.fillAlpha = 1,
    this.strokeAlpha = 1,
    this.fillPattern,
    this.strokePattern,
    this.fontSize = 0,
    this.charSpacing = 0,
    this.wordSpacing = 0,
    this.horizontalScale = 1,
    this.leading = 0,
    this.rise = 0,
    this.renderMode = 0,
  });

  _State clone() => _State(
        ctm: ctm,
        fillColour: fillColour,
        strokeColour: strokeColour,
        fillSpace: fillSpace,
        strokeSpace: strokeSpace,
        lineWidth: lineWidth,
        lineCap: lineCap,
        lineJoin: lineJoin,
        miterLimit: miterLimit,
        dashArray: dashArray,
        dashPhase: dashPhase,
        fillAlpha: fillAlpha,
        strokeAlpha: strokeAlpha,
        fillPattern: fillPattern,
        strokePattern: strokePattern,
        fontSize: fontSize,
        charSpacing: charSpacing,
        wordSpacing: wordSpacing,
        horizontalScale: horizontalScale,
        leading: leading,
        rise: rise,
        renderMode: renderMode,
      );
}

class _Renderer {
  final BLContext context;
  final unsupported = <String, int>{};
  var glyphsSkipped = 0;

  /// Por que cada fonte que não pôde ser desenhada foi recusada.
  final fontFailures = <String, PdfGlyphFailure>{};
  var imagesSkipped = 0;

  late _State state;
  final _stack = <_State>[];

  /// The path under construction, in device coordinates.
  BLPath _path = BLPath();
  var _pathEmpty = true;
  double _startX = 0, _startY = 0, _currentX = 0, _currentY = 0;

  /// A `W` or `W*` seen before the painting operator that ends the path.
  BLFillRule? _pendingClip;

  /// The text line matrix, in user space: where the current line starts.
  BLMatrix2D _textLineMatrix = BLMatrix2D.identity;

  /// The text matrix. It starts each line as a copy of the line matrix and
  /// then advances glyph by glyph, which is why the two cannot be one field.
  BLMatrix2D _textMatrix = BLMatrix2D.identity;

  /// The font selected by the last `Tf`, resolved to outlines and advances.
  PdfGlyphSource? _font;

  /// Fonts already resolved, keyed by resource name. Resolving parses the
  /// embedded program, so a page that sets the same font hundreds of times
  /// should pay for it once.
  final _fontCache = <String, PdfGlyphSource?>{};

  /// Fonte de substituição fornecida pelo chamador; veja
  /// [PdfRenderOptions.fontFallback].
  final PdfFontFallback? _fontFallback;

  _Renderer(this.context, BLMatrix2D base, {PdfFontFallback? fontFallback})
      : _fontFallback = fontFallback {
    state = _State(ctm: base);
  }

  /// How deep a form XObject may nest before the renderer gives up. Forms can
  /// legally reference each other, and a cycle would otherwise not terminate.
  static const int _maxDepth = 12;

  Future<void> run(
    Uint8List content,
    PdfDictionary? resources,
    int depth,
  ) async {
    if (depth > _maxDepth) return;
    final Iterable<PdfContentOperation> operations;
    try {
      operations = PdfContentParser.parse(content).toList();
    } on PdfContentException {
      _note('malformed-content');
      return;
    }

    for (final op in operations) {
      await _apply(op, resources, depth);
    }
  }

  void _note(String operator) {
    unsupported[operator] = (unsupported[operator] ?? 0) + 1;
  }

  Future<void> _apply(
    PdfContentOperation op,
    PdfDictionary? resources,
    int depth,
  ) async {
    switch (op.operator) {
      // --- graphics state ---
      case 'q':
        _stack.add(state.clone());
        context.save();
      case 'Q':
        if (_stack.isNotEmpty) state = _stack.removeLast();
        context.restore();
      case 'cm':
        final m = op.numbers(6);
        if (m != null) {
          state.ctm = BLMatrix2D(m[0], m[1], m[2], m[3], m[4], m[5])
              .multiply(state.ctm);
        }
      case 'w':
        final v = op.number(0);
        if (v != null && v >= 0) state.lineWidth = v;
      case 'J':
        state.lineCap = switch (op.number(0)?.toInt()) {
          1 => BLStrokeCap.round,
          2 => BLStrokeCap.square,
          _ => BLStrokeCap.butt,
        };
      case 'j':
        state.lineJoin = switch (op.number(0)?.toInt()) {
          1 => BLStrokeJoin.round,
          2 => BLStrokeJoin.bevel,
          _ => BLStrokeJoin.miterBevel,
        };
      case 'M':
        final v = op.number(0);
        if (v != null && v > 0) state.miterLimit = v;
      case 'd':
        _setDash(op);
      case 'gs':
        await _applyExtGState(op, resources, depth);
      case 'i':
      case 'ri':
        break; // Flatness and rendering intent do not change the geometry.

      // --- path construction ---
      case 'm':
        final p = op.numbers(2);
        if (p != null) _moveTo(p[0], p[1]);
      case 'l':
        final p = op.numbers(2);
        if (p != null) _lineTo(p[0], p[1]);
      case 'c':
        final p = op.numbers(6);
        if (p != null) _curveTo(p[0], p[1], p[2], p[3], p[4], p[5]);
      case 'v':
        // The first control point is the current point.
        final p = op.numbers(4);
        if (p != null) {
          _curveToDevice(
              (_currentX, _currentY), _device(p[0], p[1]), _device(p[2], p[3]));
        }
      case 'y':
        // The second control point is the end point.
        final p = op.numbers(4);
        if (p != null) {
          final end = _device(p[2], p[3]);
          _curveToDevice(_device(p[0], p[1]), end, end);
        }
      case 'h':
        _close();
      case 're':
        final r = op.numbers(4);
        if (r != null) _rectangle(r[0], r[1], r[2], r[3]);

      // --- path painting ---
      case 'n':
        await _endPath(fill: null, stroke: false);
      case 'f':
      case 'F':
        await _endPath(fill: BLFillRule.nonZero, stroke: false);
      case 'f*':
        await _endPath(fill: BLFillRule.evenOdd, stroke: false);
      case 'S':
        await _endPath(fill: null, stroke: true);
      case 's':
        _close();
        await _endPath(fill: null, stroke: true);
      case 'B':
        await _endPath(fill: BLFillRule.nonZero, stroke: true);
      case 'B*':
        await _endPath(fill: BLFillRule.evenOdd, stroke: true);
      case 'b':
        _close();
        await _endPath(fill: BLFillRule.nonZero, stroke: true);
      case 'b*':
        _close();
        await _endPath(fill: BLFillRule.evenOdd, stroke: true);
      case 'W':
        _pendingClip = BLFillRule.nonZero;
      case 'W*':
        _pendingClip = BLFillRule.evenOdd;

      // --- colour ---
      case 'g':
        _setGray(op, stroke: false);
      case 'G':
        _setGray(op, stroke: true);
      case 'rg':
        _setRgb(op, stroke: false);
      case 'RG':
        _setRgb(op, stroke: true);
      case 'k':
        _setCmyk(op, stroke: false);
      case 'K':
        _setCmyk(op, stroke: true);
      case 'cs':
        await _setSpace(op, resources, stroke: false);
      case 'CS':
        await _setSpace(op, resources, stroke: true);
      case 'sc':
      case 'scn':
        await _setComponents(op, resources, stroke: false);
      case 'SC':
      case 'SCN':
        await _setComponents(op, resources, stroke: true);
      case 'sh':
        await _paintNamedShading(op.name(0), resources);

      // --- text ---
      case 'BT':
        _textLineMatrix = BLMatrix2D.identity;
        _textMatrix = BLMatrix2D.identity;
      case 'ET':
        break;
      case 'Tf':
        state.fontSize = op.number(1) ?? state.fontSize;
        await _selectFont(op.name(0), resources);
      case 'Tc':
        state.charSpacing = op.number(0) ?? state.charSpacing;
      case 'Tw':
        state.wordSpacing = op.number(0) ?? state.wordSpacing;
      case 'Tz':
        state.horizontalScale = (op.number(0) ?? 100) / 100;
      case 'TL':
        state.leading = op.number(0) ?? state.leading;
      case 'Ts':
        state.rise = op.number(0) ?? state.rise;
      case 'Tr':
        state.renderMode = op.number(0)?.toInt() ?? state.renderMode;
      case 'Td':
        final p = op.numbers(2);
        if (p != null) _textNewline(p[0], p[1]);
      case 'TD':
        final p = op.numbers(2);
        if (p != null) {
          state.leading = -p[1];
          _textNewline(p[0], p[1]);
        }
      case 'Tm':
        final m = op.numbers(6);
        if (m != null) {
          _textLineMatrix = BLMatrix2D(m[0], m[1], m[2], m[3], m[4], m[5]);
          _textMatrix = _textLineMatrix;
        }
      case 'T*':
        _textNewline(0, -state.leading);
      case 'Tj':
      case 'TJ':
      case "'":
      case '"':
        await _showText(op);

      // --- XObjects and images ---
      case 'Do':
        await _doXObject(op, resources, depth);
      case 'BI':
        await _inlineImage(op);

      // --- marked content and compatibility, which draw nothing ---
      case 'BMC':
      case 'BDC':
      case 'EMC':
      case 'MP':
      case 'DP':
      case 'BX':
      case 'EX':
      case 'd0':
      case 'd1':
        break;

      default:
        if (op.operator.isNotEmpty) _note(op.operator);
    }
  }

  // --- geometry -------------------------------------------------------------

  /// Maps a user-space point into device space through the current CTM.
  ///
  /// Every path point goes through here, so the path handed to the rasterizer
  /// is already in device coordinates and curves flatten at the resolution
  /// they will actually be drawn at.
  (double, double) _device(double x, double y) => state.ctm.mapPoint(x, y);

  void _moveTo(double x, double y) {
    final p = _device(x, y);
    _path.moveTo(p.$1, p.$2);
    _startX = _currentX = p.$1;
    _startY = _currentY = p.$2;
    _pathEmpty = false;
  }

  void _lineTo(double x, double y) {
    if (_pathEmpty) return _moveTo(x, y);
    final p = _device(x, y);
    _path.lineTo(p.$1, p.$2);
    _currentX = p.$1;
    _currentY = p.$2;
  }

  void _curveTo(
          double x1, double y1, double x2, double y2, double x3, double y3) =>
      _curveToDevice(_device(x1, y1), _device(x2, y2), _device(x3, y3));

  void _curveToDevice(
      (double, double) c1, (double, double) c2, (double, double) end) {
    if (_pathEmpty) {
      _path.moveTo(c1.$1, c1.$2);
      _startX = _currentX = c1.$1;
      _startY = _currentY = c1.$2;
      _pathEmpty = false;
    }
    _path.cubicTo(c1.$1, c1.$2, c2.$1, c2.$2, end.$1, end.$2);
    _currentX = end.$1;
    _currentY = end.$2;
  }

  void _close() {
    if (_pathEmpty) return;
    _path.close();
    _currentX = _startX;
    _currentY = _startY;
  }

  void _rectangle(double x, double y, double w, double h) {
    // A rectangle is four transformed corners, not an axis-aligned box: under
    // a rotated CTM `re` describes a parallelogram.
    _moveTo(x, y);
    _lineTo(x + w, y);
    _lineTo(x + w, y + h);
    _lineTo(x, y + h);
    _close();
  }

  Future<void> _endPath({BLFillRule? fill, required bool stroke}) async {
    if (!_pathEmpty) {
      if (fill != null) {
        if (state.fillPattern != null) {
          await _fillPattern(_path, fill, state.fillPattern!);
        } else {
          await context.fillPath(_path,
              color: _withAlpha(state.fillColour, state.fillAlpha), rule: fill);
        }
      }
      if (stroke) {
        await _strokeCurrentPath();
      }
      final clip = _pendingClip;
      if (clip != null) context.clipToPath(_path, rule: clip);
    }
    _pendingClip = null;
    _path = BLPath();
    _pathEmpty = true;
  }

  Future<void> _strokeCurrentPath() async {
    // The path is already in device space, so the line width has to be too.
    // A uniform scale is exact; under a skew this is the average, which is
    // what a stroke of a single width can be.
    final scale = _averageScale(state.ctm);
    final options = BLStrokeOptions(
      width: state.lineWidth * scale,
      startCap: state.lineCap,
      endCap: state.lineCap,
      join: state.lineJoin,
      miterLimit: state.miterLimit,
    );
    final colour = _withAlpha(state.strokeColour, state.strokeAlpha);

    if (state.dashArray.isNotEmpty && state.dashArray.any((d) => d > 0)) {
      if (state.strokePattern != null) {
        final dashed = BLDasher.dashPath(
            _path, state.dashArray.map((d) => d * scale).toList(),
            dashOffset: state.dashPhase * scale);
        final outline = BLStroker.strokePath(dashed, options);
        await _fillPattern(outline, BLFillRule.nonZero, state.strokePattern!,
            stroke: true);
        return;
      }
      await context.strokeDashedPath(
        _path,
        dashArray: state.dashArray.map((d) => d * scale).toList(),
        dashOffset: state.dashPhase * scale,
        color: colour,
        options: options,
      );
      return;
    }
    if (state.strokePattern != null) {
      final outline = BLStroker.strokePath(_path, options);
      await _fillPattern(outline, BLFillRule.nonZero, state.strokePattern!,
          stroke: true);
      return;
    }
    await context.strokePath(_path, color: colour, options: options);
  }

  static double _averageScale(BLMatrix2D m) {
    final determinant = m.determinant.abs();
    if (determinant > 0) return math.sqrt(determinant);
    // A degenerate CTM collapses the path; fall back to the row lengths so a
    // stroke still has a width rather than vanishing.
    final x = math.sqrt(m.m00 * m.m00 + m.m01 * m.m01);
    final y = math.sqrt(m.m10 * m.m10 + m.m11 * m.m11);
    return (x + y) / 2;
  }

  // --- colour ---------------------------------------------------------------

  static int _rgb(double r, double g, double b) =>
      0xFF000000 |
      ((r * 255).round().clamp(0, 255) << 16) |
      ((g * 255).round().clamp(0, 255) << 8) |
      (b * 255).round().clamp(0, 255);

  static int _withAlpha(int colour, double alpha) {
    if (alpha >= 1) return colour;
    final a = (alpha.clamp(0.0, 1.0) * 255).round();
    return (colour & 0x00FFFFFF) | (a << 24);
  }

  void _setGray(PdfContentOperation op, {required bool stroke}) {
    final v = op.number(0);
    if (v == null) return;
    final colour = _rgb(v, v, v);
    if (stroke) {
      state.strokeColour = colour;
      state.strokeSpace = null;
      state.strokePattern = null;
    } else {
      state.fillColour = colour;
      state.fillSpace = null;
      state.fillPattern = null;
    }
  }

  void _setRgb(PdfContentOperation op, {required bool stroke}) {
    final v = op.numbers(3);
    if (v == null) return;
    final colour = _rgb(v[0], v[1], v[2]);
    if (stroke) {
      state.strokeColour = colour;
      state.strokeSpace = null;
      state.strokePattern = null;
    } else {
      state.fillColour = colour;
      state.fillSpace = null;
      state.fillPattern = null;
    }
  }

  void _setCmyk(PdfContentOperation op, {required bool stroke}) {
    final v = op.numbers(4);
    if (v == null) return;
    final colour = _rgb(
      (1 - v[0]) * (1 - v[3]),
      (1 - v[1]) * (1 - v[3]),
      (1 - v[2]) * (1 - v[3]),
    );
    if (stroke) {
      state.strokeColour = colour;
      state.strokeSpace = null;
      state.strokePattern = null;
    } else {
      state.fillColour = colour;
      state.fillSpace = null;
      state.fillPattern = null;
    }
  }

  Future<void> _setSpace(
    PdfContentOperation op,
    PdfDictionary? resources, {
    required bool stroke,
  }) async {
    final name = op.name(0);
    if (name == null) return;

    PdfColorSpace? space;
    if (const [
      'DeviceGray',
      'DeviceRGB',
      'DeviceCMYK',
      'Pattern',
      'G',
      'RGB',
      'CMYK'
    ].contains(name)) {
      space = await PdfColorSpace.makeColorSpace(PdfName(name));
    } else {
      final dictionary =
          await resources?.dictionaryEntry(PdfName('ColorSpace'));
      final entry = await dictionary?.get(PdfName(name), true);
      if (entry != null) space = await PdfColorSpace.makeColorSpace(entry);
    }
    if (space == null) {
      _note('cs:$name');
      return;
    }

    // Setting a colour space resets the colour to its initial value, which is
    // black for every device space.
    if (stroke) {
      state.strokeSpace = space;
      state.strokeColour = 0xFF000000;
      state.strokePattern = null;
    } else {
      state.fillSpace = space;
      state.fillColour = 0xFF000000;
      state.fillPattern = null;
    }
  }

  Future<void> _setComponents(PdfContentOperation op, PdfDictionary? resources,
      {required bool stroke}) async {
    final space = stroke ? state.strokeSpace : state.fillSpace;
    final components = <double>[];
    for (final operand in op.operands) {
      if (operand is PdfNumber) components.add(operand.doubleValue());
    }
    final name = op.operands.whereType<PdfName>().lastOrNull?.getValue();
    if (name != null) {
      final patterns = await resources?.dictionaryEntry(PdfName.pattern);
      final patternObject = await patterns?.get(PdfName(name), true);
      final pattern = patternObject is PdfDictionary ? patternObject : null;
      if (pattern == null) {
        _note('${stroke ? 'SCN' : 'scn'}:pattern');
      } else if (stroke) {
        state.strokePattern = pattern;
        if (components.isNotEmpty) {
          state.strokeColour = _componentsColour(components);
        }
      } else {
        state.fillPattern = pattern;
        if (components.isNotEmpty) {
          state.fillColour = _componentsColour(components);
        }
      }
      return;
    }
    if (components.isEmpty) return;

    int colour;
    if (space == null) {
      colour = switch (components.length) {
        1 => _rgb(components[0], components[0], components[0]),
        3 => _rgb(components[0], components[1], components[2]),
        4 => _rgb(
            (1 - components[0]) * (1 - components[3]),
            (1 - components[1]) * (1 - components[3]),
            (1 - components[2]) * (1 - components[3])),
        _ => 0xFF000000,
      };
    } else {
      try {
        final rgb = space.toRgb(components);
        colour = _rgb(rgb[0], rgb[1], rgb[2]);
      } on Object {
        _note('${stroke ? 'SCN' : 'scn'}:unconvertible');
        return;
      }
    }

    if (stroke) {
      state.strokeColour = colour;
      state.strokePattern = null;
    } else {
      state.fillColour = colour;
      state.fillPattern = null;
    }
  }

  static int _componentsColour(List<double> components) =>
      switch (components.length) {
        1 => _rgb(components[0], components[0], components[0]),
        3 => _rgb(components[0], components[1], components[2]),
        4 => _rgb(
            (1 - components[0]) * (1 - components[3]),
            (1 - components[1]) * (1 - components[3]),
            (1 - components[2]) * (1 - components[3])),
        _ => 0xFF000000,
      };

  Future<void> _paintNamedShading(
      String? name, PdfDictionary? resources) async {
    if (name == null || resources == null) {
      _note('sh');
      return;
    }
    final shadings = await resources.dictionaryEntry(PdfName.shading);
    final shadingObject = await shadings?.get(PdfName(name), true);
    if (shadingObject is! PdfDictionary) {
      _note('sh');
      return;
    }
    final pattern = PdfDictionary()
      ..put(PdfName('PatternType'), PdfNumber.fromInt(2))
      ..put(PdfName.shading, shadingObject);
    final surface = BLPath()
      ..moveTo(0, 0)
      ..lineTo(context.image.width.toDouble(), 0)
      ..lineTo(context.image.width.toDouble(), context.image.height.toDouble())
      ..lineTo(0, context.image.height.toDouble())
      ..close();
    await _fillShadingPattern(surface, BLFillRule.nonZero, pattern,
        stroke: false);
  }

  Future<void> _fillPattern(BLPath path, BLFillRule rule, PdfDictionary pattern,
      {bool stroke = false}) async {
    final type = await pattern.integerEntry(PdfName('PatternType'));
    if (type == 2) {
      await _fillShadingPattern(path, rule, pattern, stroke: stroke);
      return;
    }
    if (type != 1 || pattern is! PdfStream) {
      _note('scn:pattern-type-${type ?? 'missing'}');
      return;
    }
    final paintType = await pattern.integerEntry(PdfName('PaintType'));
    if (paintType != 1 && paintType != 2) {
      _note('scn:unknown-paint-type');
      return;
    }
    final bboxArray = await pattern.arrayEntry(PdfName.bBox);
    final xStep = await pattern.decimalEntry(PdfName('XStep'));
    final yStep = await pattern.decimalEntry(PdfName('YStep'));
    if (bboxArray == null ||
        bboxArray.size() != 4 ||
        xStep == null ||
        yStep == null ||
        xStep.abs() < 1e-9 ||
        yStep.abs() < 1e-9) {
      _note('scn:malformed-pattern');
      return;
    }
    final bbox = await bboxArray.toDoubleArray();
    var matrix = BLMatrix2D.identity;
    final matrixArray = await pattern.arrayEntry(PdfName.matrix);
    if (matrixArray != null && matrixArray.size() == 6) {
      final m = await matrixArray.toDoubleArray();
      matrix = BLMatrix2D(m[0], m[1], m[2], m[3], m[4], m[5]);
    }
    final patternToDevice = matrix.multiply(state.ctm);
    final sx = math.sqrt(patternToDevice.m00 * patternToDevice.m00 +
        patternToDevice.m01 * patternToDevice.m01);
    final sy = math.sqrt(patternToDevice.m10 * patternToDevice.m10 +
        patternToDevice.m11 * patternToDevice.m11);
    if (sx < 1e-9 || sy < 1e-9) return;
    final tileWidth = math.max(1, (xStep.abs() * sx).ceil());
    final tileHeight = math.max(1, (yStep.abs() * sy).ceil());
    if (tileWidth * tileHeight > 16 * 1000 * 1000) {
      _note('scn:pattern-too-large');
      return;
    }
    final px = tileWidth / xStep.abs();
    final py = tileHeight / yStep.abs();
    final patternToPixel =
        BLMatrix2D(px, 0, 0, -py, -bbox[0] * px, bbox[3] * py);
    final tile = BLImage(tileWidth, tileHeight)..clear(0x00000000);
    final tileContext = BLContext(tile);
    final nested =
        _Renderer(tileContext, patternToPixel, fontFallback: _fontFallback);
    if (paintType == 2) {
      final baseColour = stroke ? state.strokeColour : state.fillColour;
      nested.state.fillColour = baseColour;
      nested.state.strokeColour = baseColour;
    }
    final patternResources = await pattern.dictionaryEntry(PdfName.resources);
    final bytes = await pattern.getBytes();
    if (bytes != null) await nested.run(bytes, patternResources, 0);
    tileContext.flush();
    final graphicsAlpha = stroke ? state.strokeAlpha : state.fillAlpha;
    if (graphicsAlpha < 1) {
      final alpha = graphicsAlpha.clamp(0.0, 1.0);
      for (var i = 0; i < tile.pixels.length; i++) {
        final pixel = tile.pixels[i];
        final a = (((pixel >>> 24) & 0xff) * alpha).round();
        tile.pixels[i] = (pixel & 0x00ffffff) | (a << 24);
      }
    }
    for (final entry in nested.unsupported.entries) {
      unsupported[entry.key] = (unsupported[entry.key] ?? 0) + entry.value;
    }
    glyphsSkipped += nested.glyphsSkipped;
    imagesSkipped += nested.imagesSkipped;
    fontFailures.addAll(nested.fontFailures);

    final deviceToPattern = patternToDevice.invert();
    if (deviceToPattern == null) return;
    context.setPattern(BLPattern(
      image: tile,
      extendModeX: BLGradientExtendMode.repeat,
      extendModeY: BLGradientExtendMode.repeat,
      transform: deviceToPattern.multiply(patternToPixel),
    ));
    await context.fillPath(path, rule: rule);
    context.setFillStyle(stroke ? state.strokeColour : state.fillColour);
  }

  Future<void> _fillShadingPattern(
      BLPath path, BLFillRule rule, PdfDictionary pattern,
      {required bool stroke}) async {
    final shadingObject = await pattern.get(PdfName.shading, true);
    if (shadingObject is! PdfDictionary) {
      _note('scn:malformed-shading-pattern');
      return;
    }
    final shading = shadingObject;
    final shadingType = await shading.integerEntry(PdfName.shadingType);
    final expectedCoords = shadingType == 2 ? 4 : (shadingType == 3 ? 6 : 0);
    final coordsArray = await shading.arrayEntry(PdfName.coords);
    final function =
        await PdfFunction.parse(await shading.get(PdfName.function, true));
    final colorObject = await shading.get(PdfName.colorSpace, true);
    final colorSpace = colorObject == null
        ? null
        : await PdfColorSpace.makeColorSpace(colorObject);
    if (expectedCoords == 0 ||
        coordsArray == null ||
        coordsArray.size() != expectedCoords ||
        function == null ||
        colorSpace == null) {
      _note('scn:unsupported-shading-pattern');
      return;
    }
    final coords = await coordsArray.toDoubleArray();
    var domainStart = 0.0;
    var domainEnd = 1.0;
    final shadingDomain = await shading.arrayEntry(PdfName('Domain'));
    if (shadingDomain != null && shadingDomain.size() == 2) {
      final values = await shadingDomain.toDoubleArray();
      domainStart = values[0];
      domainEnd = values[1];
    }
    var matrix = BLMatrix2D.identity;
    final matrixArray = await pattern.arrayEntry(PdfName.matrix);
    if (matrixArray != null && matrixArray.size() == 6) {
      final values = await matrixArray.toDoubleArray();
      matrix = BLMatrix2D(
          values[0], values[1], values[2], values[3], values[4], values[5]);
    }
    final toDevice = matrix.multiply(state.ctm);
    final alpha = stroke ? state.strokeAlpha : state.fillAlpha;
    final stops = <BLGradientStop>[];
    for (var index = 0; index <= 256; index++) {
      final offset = index / 256;
      try {
        final input = domainStart + offset * (domainEnd - domainStart);
        final components = function.evaluate([input]);
        final rgb = colorSpace.toRgb(components);
        stops.add(BLGradientStop(
            offset, _withAlpha(_rgb(rgb[0], rgb[1], rgb[2]), alpha)));
      } on Object {
        _note('scn:shading-colour');
        return;
      }
    }
    if (shadingType == 2) {
      final p0 = toDevice.mapPoint(coords[0], coords[1]);
      final p1 = toDevice.mapPoint(coords[2], coords[3]);
      context.setLinearGradient(BLLinearGradient(
          p0: BLPoint(p0.$1, p0.$2), p1: BLPoint(p1.$1, p1.$2), stops: stops));
    } else {
      final c0 = toDevice.mapPoint(coords[0], coords[1]);
      final c1 = toDevice.mapPoint(coords[3], coords[4]);
      final scale = _averageScale(toDevice);
      context.setRadialGradient(BLRadialGradient(
          c0: BLPoint(c0.$1, c0.$2),
          c1: BLPoint(c1.$1, c1.$2),
          r0: coords[2] * scale,
          r1: coords[5] * scale,
          stops: stops));
    }
    await context.fillPath(path, rule: rule);
    context.setFillStyle(stroke ? state.strokeColour : state.fillColour);
  }

  // --- graphics state dictionary --------------------------------------------

  Future<void> _applyExtGState(
      PdfContentOperation op, PdfDictionary? resources, int depth) async {
    final name = op.name(0);
    if (name == null || resources == null) return;
    final states = await resources.dictionaryEntry(PdfName('ExtGState'));
    final gs = await states?.dictionaryEntry(PdfName(name));
    if (gs == null) return;

    final lineWidth = await gs.decimalEntry(PdfName('LW'));
    if (lineWidth != null && lineWidth >= 0) state.lineWidth = lineWidth;

    final fillAlpha = await gs.decimalEntry(PdfName('ca'));
    if (fillAlpha != null) state.fillAlpha = fillAlpha.clamp(0.0, 1.0);

    final strokeAlpha = await gs.decimalEntry(PdfName('CA'));
    if (strokeAlpha != null) state.strokeAlpha = strokeAlpha.clamp(0.0, 1.0);

    if (gs.containsKey(PdfName('SMask'))) {
      final maskObject = await gs.get(PdfName('SMask'), true);
      if (maskObject is PdfDictionary) {
        await _applySoftMask(maskObject, resources, depth);
      } else if (maskObject is PdfName && maskObject.getValue() != 'None') {
        _note('gs:SMask');
      }
    }
    final blend = await gs.nameEntry(PdfName('BM'));
    final blendName = blend?.getValue();
    if (blendName != null &&
        blendName != 'Normal' &&
        blendName != 'Compatible') {
      _note('gs:BM/$blendName');
    }
  }

  Future<void> _applySoftMask(
      PdfDictionary mask, PdfDictionary? resources, int depth) async {
    if (depth >= _maxDepth) {
      _note('gs:SMask-depth');
      return;
    }
    final group = await mask.streamEntry(PdfName('G'));
    if (group == null) {
      _note('gs:SMask-missing-group');
      return;
    }
    final subtype = (await mask.nameEntry(PdfName.s))?.getValue();
    if (subtype != 'Alpha' && subtype != 'Luminosity') {
      _note('gs:SMask-${subtype ?? 'missing-subtype'}');
      return;
    }

    var groupToDevice = state.ctm;
    final matrix = await group.arrayEntry(PdfName.matrix);
    if (matrix != null && matrix.size() == 6) {
      final m = await matrix.toDoubleArray();
      groupToDevice = BLMatrix2D(m[0], m[1], m[2], m[3], m[4], m[5])
          .multiply(groupToDevice);
    }
    final surface = BLImage(context.image.width, context.image.height)
      ..clear(0x00000000);
    final maskContext = BLContext(surface);
    final nested =
        _Renderer(maskContext, groupToDevice, fontFallback: _fontFallback);

    final bbox = await group.arrayEntry(PdfName.bBox);
    if (bbox != null && bbox.size() == 4) {
      final b = await bbox.toDoubleArray();
      nested._rectangle(math.min(b[0], b[2]), math.min(b[1], b[3]),
          (b[2] - b[0]).abs(), (b[3] - b[1]).abs());
      maskContext.clipToPath(nested._path);
      nested._path = BLPath();
      nested._pathEmpty = true;
    }
    final groupResources =
        await group.dictionaryEntry(PdfName.resources) ?? resources;
    final content = await group.getBytes();
    if (content != null) await nested.run(content, groupResources, depth + 1);
    maskContext.flush();

    final coverage = Uint8List(surface.pixels.length);
    for (var i = 0; i < coverage.length; i++) {
      final pixel = surface.pixels[i];
      final alpha = (pixel >>> 24) & 0xff;
      if (subtype == 'Alpha') {
        coverage[i] = alpha;
      } else {
        final red = (pixel >>> 16) & 0xff;
        final green = (pixel >>> 8) & 0xff;
        final blue = pixel & 0xff;
        final luminance = (red * 299 + green * 587 + blue * 114 + 500) ~/ 1000;
        coverage[i] = (luminance * alpha + 127) ~/ 255;
      }
    }
    context.intersectClipMask(coverage);
    for (final entry in nested.unsupported.entries) {
      unsupported[entry.key] = (unsupported[entry.key] ?? 0) + entry.value;
    }
    glyphsSkipped += nested.glyphsSkipped;
    imagesSkipped += nested.imagesSkipped;
    fontFailures.addAll(nested.fontFailures);
    if (mask.containsKey(PdfName('TR'))) _note('gs:SMask-transfer');
  }

  void _setDash(PdfContentOperation op) {
    if (op.operands.length != 2) return;
    final array = op.operands[0];
    if (array is! PdfArray) return;
    final pattern = <double>[];
    for (var i = 0; i < array.size(); i++) {
      final value = array.subList(i, i + 1).first;
      if (value is PdfNumber && value.doubleValue() >= 0) {
        pattern.add(value.doubleValue());
      }
    }
    state.dashArray = pattern;
    state.dashPhase = op.number(1) ?? 0;
  }

  // --- text positioning -----------------------------------------------------

  void _textNewline(double tx, double ty) {
    _textLineMatrix = BLMatrix2D(1, 0, 0, 1, tx, ty).multiply(_textLineMatrix);
    // Uma nova linha reinicia a matriz de texto a partir da matriz de linha:
    // os avanços de glifo da linha anterior não se acumulam na próxima.
    _textMatrix = _textLineMatrix;
  }

  // --- text -----------------------------------------------------------------

  /// Resolves the `Tf` operand to a font, remembering the result per page.
  Future<void> _selectFont(String? name, PdfDictionary? resources) async {
    if (name == null) {
      _font = null;
      return;
    }
    if (_fontCache.containsKey(name)) {
      _font = _fontCache[name];
      return;
    }
    PdfGlyphSource? resolved;
    try {
      resolved = await PdfGlyphSource.resolve(resources, name,
          fallback: _fontFallback);
    } catch (_) {
      // A malformed font dictionary must not abort the page; the report says
      // the text was skipped and the rest of the content still draws.
      resolved = null;
    }
    _fontCache[name] = resolved;
    _font = resolved;
    final failure = resolved?.failure;
    if (failure != null) {
      fontFailures[name] = failure;
    }
  }

  /// Draws `Tj`, `TJ`, `'` and `"`.
  Future<void> _showText(PdfContentOperation op) async {
    var operandIndex = 0;
    switch (op.operator) {
      case "'":
        _textNewline(0, -state.leading);
      case '"':
        // `aw ac string "` sets word and character spacing before showing.
        state.wordSpacing = op.number(0) ?? state.wordSpacing;
        state.charSpacing = op.number(1) ?? state.charSpacing;
        operandIndex = 2;
        _textNewline(0, -state.leading);
    }

    if (operandIndex >= op.operands.length) return;
    final operand = op.operands[operandIndex];

    if (operand is PdfString) {
      await _showString(operand.getValueBytes());
      return;
    }

    if (operand is PdfArray) {
      // In `TJ` a number displaces the next glyph by -n/1000 text units,
      // which is how justified text and kerning corrections are encoded.
      for (var i = 0; i < operand.size(); i++) {
        final item = await operand.get(i);
        if (item is PdfString) {
          await _showString(item.getValueBytes());
        } else if (item is PdfNumber) {
          _advanceText(-item.doubleValue() /
              1000.0 *
              state.fontSize *
              state.horizontalScale);
        }
      }
      return;
    }

    glyphsSkipped++;
  }

  Future<void> _showString(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return;

    final font = _font;
    if (font == null || !font.isDrawable) {
      // Positioning still has to happen even when the glyphs cannot be drawn,
      // or everything after this run on the line would sit in the wrong place.
      // Without metrics the best available estimate is half an em per code.
      final codes = font?.codes(bytes) ?? bytes;
      for (final code in codes) {
        final width = font?.width(code) ?? 0.5;
        _advanceForCode(code, width, composite: font?.composite ?? false);
      }
      glyphsSkipped++;
      return;
    }

    // Render mode 3 is invisible and 7 only adds to the clip; neither paints.
    // This is what makes the text layer of a scanned page stay hidden.
    final invisible = state.renderMode == 3 || state.renderMode == 7;
    final stroke = state.renderMode == 1 || state.renderMode == 5;

    for (final code in font.codes(bytes)) {
      if (!invisible) {
        await _drawGlyph(font, code, stroke: stroke);
      }
      _advanceForCode(code, font.width(code), composite: font.composite);
    }
  }

  /// Advances the text matrix past one glyph.
  ///
  /// ISO 32000-1 §9.4.4: `tx = ((w0 - Tj/1000) * Tfs + Tc + Tw) * Th`. The
  /// `Tj` displacement is applied separately by the array branch above.
  void _advanceForCode(int code, double width, {required bool composite}) {
    var advance = width * state.fontSize + state.charSpacing;
    // Word spacing applies to the single byte 32, and never to a two-byte
    // code — a composite font can legitimately have 0x0020 as half a code.
    if (code == 32 && !composite) advance += state.wordSpacing;
    _advanceText(advance * state.horizontalScale);
  }

  void _advanceText(double tx) {
    _textMatrix = BLMatrix2D(1, 0, 0, 1, tx, 0).multiply(_textMatrix);
  }

  /// Fills (or strokes) one glyph's outline.
  Future<void> _drawGlyph(
    PdfGlyphSource font,
    int code, {
    required bool stroke,
  }) async {
    final face = font.face!;
    final gid = font.glyph(code);
    if (gid == null) {
      glyphsSkipped++;
      return;
    }

    final outline = face.glyphOutlineUnits(gid);
    if (outline == null || outline.vertices.isEmpty) {
      return; // blank, e.g. space
    }

    // Glyph space to text space, then the text state parameters, then the
    // text matrix, then the CTM. Composing once and mapping each vertex is
    // what keeps the curve flattening in device resolution.
    //
    // `glyphOutlineUnits` returns y growing downwards, because its rasterizer
    // works in screen coordinates. A PDF page is y-up, so the device matrix
    // built by `_deviceMatrix` already flips the axis — and the two flips
    // cancel, which is why the glyphs come out the right way up. Changing
    // either convention alone turns the text upside down.
    final scale = state.fontSize / face.unitsPerEm;
    final parameters = BLMatrix2D(
      scale * state.horizontalScale,
      0,
      0,
      scale,
      0,
      state.rise,
    );
    final transform = parameters.multiply(_textMatrix).multiply(state.ctm);

    final source = outline.vertices;
    final mapped = List<double>.filled(source.length, 0);
    for (var i = 0; i < source.length; i += 2) {
      final (x, y) = transform.mapPoint(source[i], source[i + 1]);
      mapped[i] = x;
      mapped[i + 1] = y;
    }

    if (stroke) {
      final scale = _averageScale(state.ctm);
      await context.strokePolygon(
        mapped,
        contourVertexCounts: outline.contourVertexCounts,
        color: _withAlpha(state.strokeColour, state.strokeAlpha),
        options: BLStrokeOptions(
          width: state.lineWidth * scale,
          startCap: state.lineCap,
          endCap: state.lineCap,
          join: state.lineJoin,
          miterLimit: state.miterLimit,
        ),
      );
    } else {
      // Glyph outlines are always non-zero: counters are wound the other way
      // round, and even-odd would punch holes through overlapping contours.
      await context.fillPolygon(
        mapped,
        contourVertexCounts: outline.contourVertexCounts,
        color: _withAlpha(state.fillColour, state.fillAlpha),
        rule: BLFillRule.nonZero,
      );
    }
  }

  // --- XObjects -------------------------------------------------------------

  Future<void> _doXObject(
    PdfContentOperation op,
    PdfDictionary? resources,
    int depth,
  ) async {
    final name = op.name(0);
    if (name == null || resources == null) return;
    final xobjects = await resources.dictionaryEntry(PdfName('XObject'));
    final xobject = await xobjects?.streamEntry(PdfName(name));
    if (xobject == null) return;

    final subtype = (await xobject.nameEntry(PdfName.subtype))?.getValue();
    if (subtype == 'Image') {
      await _drawImage(xobject);
      return;
    }
    if (subtype != 'Form') {
      _note('Do:$subtype');
      return;
    }

    // A form runs with its own matrix and resources, inside a saved state, and
    // clipped to its bounding box.
    final saved = state.clone();
    final savedStack = _stack.length;
    context.save();

    final matrix = await xobject.arrayEntry(PdfName('Matrix'));
    if (matrix != null && matrix.size() == 6) {
      final m = <double>[];
      for (var i = 0; i < 6; i++) {
        final value = await matrix.get(i);
        m.add(value is PdfNumber
            ? value.doubleValue()
            : (i == 0 || i == 3 ? 1 : 0));
      }
      state.ctm =
          BLMatrix2D(m[0], m[1], m[2], m[3], m[4], m[5]).multiply(state.ctm);
    }

    final bbox = await xobject.arrayEntry(PdfName('BBox'));
    if (bbox != null && bbox.size() == 4) {
      final b = <double>[];
      for (var i = 0; i < 4; i++) {
        final value = await bbox.get(i);
        b.add(value is PdfNumber ? value.doubleValue() : 0);
      }
      _rectangle(math.min(b[0], b[2]), math.min(b[1], b[3]),
          (b[2] - b[0]).abs(), (b[3] - b[1]).abs());
      context.clipToPath(_path);
      _path = BLPath();
      _pathEmpty = true;
    }

    final formResources =
        await xobject.dictionaryEntry(PdfName.resources) ?? resources;
    final content = await xobject.getBytes();
    if (content != null) {
      await run(content, formResources, depth + 1);
    }

    context.restore();
    while (_stack.length > savedStack) {
      _stack.removeLast();
    }
    state = saved;
  }

  Future<void> _inlineImage(PdfContentOperation op) async {
    final dictionary = op.inlineImage;
    final data = op.inlineImageData;
    if (dictionary == null || data == null) return;
    await _drawImage(inlineImageToStream(dictionary, data));
  }

  /// Draws an image into the unit square of the current CTM, which is where
  /// PDF places every image regardless of its pixel size.
  Future<void> _drawImage(PdfStream stream) async {
    final decoded = await PdfImageDecoder.decode(stream);
    if (decoded == null) {
      imagesSkipped++;
      return;
    }

    // The unit square maps to the image's own pixel grid, with y flipped
    // because image row 0 is the *top* while the unit square's y runs up.
    final placement = BLMatrix2D(
      1 / decoded.width,
      0,
      0,
      -1 / decoded.height,
      0,
      1,
    ).multiply(state.ctm);
    final inverse = placement.invert();
    if (inverse == null) return; // A degenerate CTM draws nothing.

    final interpolate = await stream.flagEntry(PdfName('Interpolate')) ?? false;

    // The area to cover is the unit square through the CTM.
    final path = BLPath();
    final corners = [
      state.ctm.mapPoint(0, 0),
      state.ctm.mapPoint(1, 0),
      state.ctm.mapPoint(1, 1),
      state.ctm.mapPoint(0, 1),
    ];
    path.moveTo(corners[0].$1, corners[0].$2);
    for (var i = 1; i < 4; i++) {
      path.lineTo(corners[i].$1, corners[i].$2);
    }
    path.close();

    final stencil = decoded.stencil;
    if (stencil != null) {
      // A stencil paints the current fill colour where its samples say so.
      final surface = BLImage(decoded.width, decoded.height);
      final colour = _withAlpha(state.fillColour, state.fillAlpha) & 0x00FFFFFF;
      final alpha = ((state.fillAlpha.clamp(0.0, 1.0)) * 255).round();
      for (var i = 0; i < stencil.length; i++) {
        final coverage = stencil[i] * alpha ~/ 255;
        surface.pixels[i] = (coverage << 24) | colour;
      }
      await _fillWithPattern(path, surface, inverse, interpolate);
      return;
    }

    final rgba = decoded.rgba!;
    final surface = BLImage(decoded.width, decoded.height);
    final globalAlpha = state.fillAlpha.clamp(0.0, 1.0);
    for (var i = 0, at = 0; i < surface.pixels.length; i++, at += 4) {
      final a = (rgba[at + 3] * globalAlpha).round().clamp(0, 255);
      surface.pixels[i] =
          (a << 24) | (rgba[at] << 16) | (rgba[at + 1] << 8) | rgba[at + 2];
    }
    await _fillWithPattern(path, surface, inverse, interpolate);
  }

  Future<void> _fillWithPattern(BLPath path, BLImage surface,
      BLMatrix2D inverse, bool interpolate) async {
    // The fetcher maps a device pixel back to a source pixel, so it wants the
    // inverse of the placement matrix.
    //
    // Point sampling is the default because the format says so: an image is
    // interpolated only when its dictionary sets /Interpolate true. Filtering
    // everything would blur a barcode or a screenshot placed at 1:1.
    context.setPattern(BLPattern(
      image: surface,
      transform: inverse,
      filter: interpolate ? BLPatternFilter.bilinear : BLPatternFilter.nearest,
    ));
    await context.fillPath(path, rule: BLFillRule.nonZero);
    context.setFillStyle(state.fillColour);
  }
}
