import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dgfx/dgfx.dart';

import '../kernel/geom/rectangle.dart';
import '../kernel/pdf/colorspace/pdf_color_space.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_page.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../kernel/pdf/pdf_string.dart';
import '../kernel/pdf/function/pdf_function.dart';
import '../io/image/png_encoder.dart';
import 'content_parser.dart';
import 'glyph_source.dart';
import 'image_decoder.dart';
import 'standard_fonts.dart';
import 'system_fonts.dart';
import 'type3_font.dart';

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
    this.useStandardFonts = true,
    this.useSystemFonts = false,
  });

  /// Desenha com as URW Core 35 embutidas o que o PDF não embutiu.
  ///
  /// Ligado por padrão. As URW são as substitutas metricamente compatíveis das
  /// catorze fontes padrão — o mesmo conjunto que o Ghostscript usa —, então o
  /// `/Widths` do PDF continua descrevendo a linha que se vê.
  ///
  /// O padrão pesa dois erros. Desenhar com outra tipografia sem avisar é
  /// enganoso; devolver a página em branco também é, e é o erro mais grave dos
  /// dois, porque some com o conteúdo em vez de aproximá-lo. Praticamente todo
  /// PDF do mundo real referencia ao menos uma das catorze sem carregá-la, e
  /// nenhum leitor conhecido responde a isso com uma página vazia. O desempate
  /// é o relatório: toda substituição aparece em
  /// [PdfRenderReport.fontsSubstituted], nomeada, de modo que quem precisa de
  /// fidelidade consegue ver que não a teve.
  ///
  /// Desligue quando não desenhar for melhor do que desenhar diferente. Fora
  /// do VM isto não tem efeito: o caminho web não carrega os programas.
  /// [fontFallback], quando fornecido, tem precedência.
  final bool useStandardFonts;

  /// Também procura nas fontes instaladas na máquina.
  ///
  /// Desligado por padrão, de propósito: o catálogo varia de máquina para
  /// máquina, e com ele a página deixa de ser reproduzível — duas execuções do
  /// mesmo documento podem sair diferentes. Ligue quando a tipografia real
  /// valer mais do que a reprodutibilidade, por exemplo quando o documento
  /// referencia fontes instaladas localmente sem embuti-las.
  ///
  /// Quando ligado, o sistema responde primeiro: se a fonte que o produtor
  /// nomeou está instalada, ela é mais fiel do que qualquer substituta. O que
  /// o sistema não tiver cai nas URW embutidas. Também sem efeito fora do VM.
  final bool useSystemFonts;

  /// Supplies a typeface for text whose font the PDF does not embed.
  ///
  /// Most real documents reference at least one font without carrying it —
  /// the standard fourteen, or whatever the producer assumed the reader has.
  /// The package covers the fourteen itself, with the bundled URW faces
  /// ([useStandardFonts]); this hook is how a caller substitutes something
  /// else, and the only way to draw such text on the web, where the bundled
  /// programs are not carried. It takes precedence over both built-in
  /// resolvers.
  ///
  /// ```dart
  /// PdfRenderOptions(fontFallback: (request) async =>
  ///     File(request.isSerif ? 'serif.ttf' : 'sans.ttf').readAsBytes());
  /// ```
  final PdfFontFallback? fontFallback;
}

/// The blend modes of ISO 32000-1 clause 11.3.5.
///
/// The twelve separable modes apply [_BlendMode.blendChannel] to each additive
/// component independently; the four non-separable ones (Table 137) work on
/// the RGB triple as a whole through `Lum`, `SetLum`, `Sat` and `SetSat`.
enum _BlendMode {
  normal,
  multiply,
  screen,
  overlay,
  darken,
  lighten,
  colorDodge,
  colorBurn,
  hardLight,
  softLight,
  difference,
  exclusion,
  hue,
  saturation,
  color,
  luminosity;

  bool get isSeparable => index < _BlendMode.hue.index;

  /// The named modes of Tables 136 and 137. `Compatible` is `Normal` by
  /// definition and exists only for pre-1.4 documents.
  static _BlendMode? byName(String name) => switch (name) {
        'Normal' || 'Compatible' => _BlendMode.normal,
        'Multiply' => _BlendMode.multiply,
        'Screen' => _BlendMode.screen,
        'Overlay' => _BlendMode.overlay,
        'Darken' => _BlendMode.darken,
        'Lighten' => _BlendMode.lighten,
        'ColorDodge' => _BlendMode.colorDodge,
        'ColorBurn' => _BlendMode.colorBurn,
        'HardLight' => _BlendMode.hardLight,
        'SoftLight' => _BlendMode.softLight,
        'Difference' => _BlendMode.difference,
        'Exclusion' => _BlendMode.exclusion,
        'Hue' => _BlendMode.hue,
        'Saturation' => _BlendMode.saturation,
        'Color' => _BlendMode.color,
        'Luminosity' => _BlendMode.luminosity,
        _ => null,
      };

  /// `B(cb, cs)` for a separable mode, on one component in 0..1.
  double blendChannel(double cb, double cs) {
    switch (this) {
      case _BlendMode.normal:
        return cs;
      case _BlendMode.multiply:
        return cb * cs;
      case _BlendMode.screen:
        return cb + cs - cb * cs;
      case _BlendMode.overlay:
        return _BlendMode.hardLight.blendChannel(cs, cb);
      case _BlendMode.darken:
        return math.min(cb, cs);
      case _BlendMode.lighten:
        return math.max(cb, cs);
      case _BlendMode.colorDodge:
        if (cb <= 0) return 0;
        if (cs >= 1) return 1;
        return math.min(1.0, cb / (1 - cs));
      case _BlendMode.colorBurn:
        if (cb >= 1) return 1;
        if (cs <= 0) return 0;
        return 1 - math.min(1.0, (1 - cb) / cs);
      case _BlendMode.hardLight:
        return cs <= 0.5
            ? _BlendMode.multiply.blendChannel(cb, 2 * cs)
            : _BlendMode.screen.blendChannel(cb, 2 * cs - 1);
      case _BlendMode.softLight:
        if (cs <= 0.5) return cb - (1 - 2 * cs) * cb * (1 - cb);
        // D(x) is not simply sqrt(x): below a quarter the spec substitutes a
        // cubic so the curve stays continuous and finite at the origin.
        final d = cb <= 0.25
            ? ((16 * cb - 12) * cb + 4) * cb
            : math.sqrt(cb.clamp(0.0, 1.0));
        return cb + (2 * cs - 1) * (d - cb);
      case _BlendMode.difference:
        return (cb - cs).abs();
      case _BlendMode.exclusion:
        return cb + cs - 2 * cb * cs;
      case _BlendMode.hue:
      case _BlendMode.saturation:
      case _BlendMode.color:
      case _BlendMode.luminosity:
        return cs;
    }
  }

  /// `B(Cb, Cs)` for a non-separable mode, writing into [out].
  void blendColour(List<double> cb, List<double> cs, List<double> out) {
    switch (this) {
      case _BlendMode.hue:
        _setSat(cs, _sat(cb), out);
        _setLum(out, _lum(cb), out);
      case _BlendMode.saturation:
        _setSat(cb, _sat(cs), out);
        _setLum(out, _lum(cb), out);
      case _BlendMode.color:
        _setLum(cs, _lum(cb), out);
      case _BlendMode.luminosity:
        _setLum(cb, _lum(cs), out);
      default:
        out[0] = cs[0];
        out[1] = cs[1];
        out[2] = cs[2];
    }
  }

  static double _lum(List<double> c) => 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2];

  static double _sat(List<double> c) =>
      math.max(c[0], math.max(c[1], c[2])) -
      math.min(c[0], math.min(c[1], c[2]));

  /// `SetLum` followed by `ClipColor`, clause 11.3.5.3.
  static void _setLum(List<double> c, double l, List<double> out) {
    final d = l - _lum(c);
    out[0] = c[0] + d;
    out[1] = c[1] + d;
    out[2] = c[2] + d;
    _clipColour(out);
  }

  static void _clipColour(List<double> c) {
    final l = _lum(c);
    final n = math.min(c[0], math.min(c[1], c[2]));
    final x = math.max(c[0], math.max(c[1], c[2]));
    if (n < 0 && l != n) {
      for (var i = 0; i < 3; i++) {
        c[i] = l + ((c[i] - l) * l) / (l - n);
      }
    }
    if (x > 1 && x != l) {
      for (var i = 0; i < 3; i++) {
        c[i] = l + ((c[i] - l) * (1 - l)) / (x - l);
      }
    }
  }

  /// `SetSat`: stretches the colour so its maximum minus its minimum is [s],
  /// keeping the relative position of the middle component.
  static void _setSat(List<double> c, double s, List<double> out) {
    var maximum = 0, middle = 1, minimum = 2;
    void order() {
      final indices = [0, 1, 2]..sort((a, b) => c[a].compareTo(c[b]));
      minimum = indices[0];
      middle = indices[1];
      maximum = indices[2];
    }

    order();
    if (c[maximum] > c[minimum]) {
      out[middle] = ((c[middle] - c[minimum]) * s) / (c[maximum] - c[minimum]);
      out[maximum] = s;
    } else {
      out[middle] = 0;
      out[maximum] = 0;
    }
    out[minimum] = 0;
  }
}

/// An offscreen surface used to composite one object, or one transparency
/// group, with a blend mode the rasterizer cannot apply directly.
class _LayerSurface {
  final BLImage image;
  final BLContext context;

  /// What the layer's clip was configured from, kept by identity so a page
  /// that draws thousands of blended objects under one clip only pays for
  /// copying the mask once.
  Uint8List? clipMask;
  Uint8List? opacityMask;
  BLRectI? clipRect;
  var configured = false;

  _LayerSurface(this.image) : context = BLContext(image);
}

class _MeshBitReader {
  final Uint8List bytes;
  int bitOffset = 0;
  _MeshBitReader(this.bytes);

  int get remaining => bytes.length * 8 - bitOffset;

  int read(int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      value =
          (value << 1) | ((bytes[bitOffset >> 3] >> (7 - (bitOffset & 7))) & 1);
      bitOffset++;
    }
    return value;
  }
}

class _MeshVertex {
  final double x, y, r, g, b;
  final List<double>? functionInputs;
  const _MeshVertex(this.x, this.y, this.r, this.g, this.b,
      [this.functionInputs]);

  _MeshVertex transform(BLMatrix2D matrix) {
    final point = matrix.mapPoint(x, y);
    return _MeshVertex(point.$1, point.$2, r, g, b, functionInputs);
  }

  double distanceTo(_MeshVertex other) =>
      math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2));

  static _MeshVertex interpolate(_MeshVertex a, _MeshVertex b, _MeshVertex c,
      int alongB, int alongC, int divisions) {
    final wb = alongB / divisions;
    final wc = alongC / divisions;
    final wa = 1 - wb - wc;
    final inputs = a.functionInputs == null ||
            b.functionInputs == null ||
            c.functionInputs == null
        ? null
        : <double>[
            for (var i = 0; i < a.functionInputs!.length; i++)
              a.functionInputs![i] * wa +
                  b.functionInputs![i] * wb +
                  c.functionInputs![i] * wc,
          ];
    return _MeshVertex(
      a.x * wa + b.x * wb + c.x * wc,
      a.y * wa + b.y * wb + c.y * wc,
      a.r * wa + b.r * wb + c.r * wc,
      a.g * wa + b.g * wb + c.g * wc,
      a.b * wa + b.b * wb + c.b * wc,
      inputs,
    );
  }
}

/// Collects the triangles of one mesh shading so the whole mesh reaches the
/// rasterizer as a single path.
///
/// Painting facet by facet and compositing each one with `srcOver` leaves a
/// light seam along every shared edge: two antialiased edges carrying half
/// coverage each do not add up to the full coverage the interior needs, so
/// the background shows through in a grid. Handing every triangle to
/// [BLContext.fillTriangleMesh] as a contour of one non-zero path makes the
/// interior edges cancel — each is walked in opposite directions by the two
/// triangles that share it — and leaves the antialiasing on the silhouette,
/// which is where it belongs. Each vertex carries its own colour, so the fill
/// is a true Gouraud interpolation rather than the average of three corners.
class _MeshAccumulator {
  final List<double> _xy = <double>[];
  final List<int> _colours = <int>[];
  final List<int> _indices = <int>[];

  /// Vertices are shared between adjacent facets, so the same object is
  /// emitted once and referenced by index. Identity, not equality: two
  /// vertices that merely happen to coincide stay separate.
  final Map<_MeshVertex, int> _slots = Map<_MeshVertex, int>.identity();

  bool get isEmpty => _indices.isEmpty;

  /// Adds one triangle whose vertices are already in device space.
  void addTriangle(
      _MeshVertex a, _MeshVertex b, _MeshVertex c, double alpha) {
    _indices
      ..add(_slot(a, alpha))
      ..add(_slot(b, alpha))
      ..add(_slot(c, alpha));
  }

  int _slot(_MeshVertex vertex, double alpha) {
    final existing = _slots[vertex];
    if (existing != null) return existing;
    final index = _colours.length;
    _xy
      ..add(vertex.x)
      ..add(vertex.y);
    _colours.add(
        _Renderer._withAlpha(_Renderer._rgb(vertex.r, vertex.g, vertex.b),
            alpha));
    _slots[vertex] = index;
    return index;
  }

  /// Adds a triangle painted in one colour.
  ///
  /// A parametric mesh samples its colour once per facet, because the
  /// function it runs the parameter through need not be affine. The three
  /// vertices therefore get slots of their own: the facet next door samples a
  /// different colour at the very same point.
  void addFlatTriangle(
      _MeshVertex a, _MeshVertex b, _MeshVertex c, int colour) {
    for (final vertex in <_MeshVertex>[a, b, c]) {
      _indices.add(_colours.length);
      _xy
        ..add(vertex.x)
        ..add(vertex.y);
      _colours.add(colour);
    }
  }

  Future<void> paint(BLContext context) async {
    if (_indices.isEmpty) return;
    await context.fillTriangleMesh(
      Float64List.fromList(_xy),
      Uint32List.fromList(_colours),
      Int32List.fromList(_indices),
    );
  }
}

class _MeshPoint {
  final double x, y;
  const _MeshPoint(this.x, this.y);

  _MeshPoint transform(BLMatrix2D matrix) {
    final point = matrix.mapPoint(x, y);
    return _MeshPoint(point.$1, point.$2);
  }
}

class _TensorPatch {
  /// Control points indexed as `column * 4 + row` (`p00` through `p33`).
  final List<_MeshPoint> points;

  /// Corner inputs in the PDF order c00, c03, c33, c30.
  final List<List<double>> corners;
  const _TensorPatch(this.points, this.corners);

  _MeshPoint evaluate(double u, double v) {
    final bu = _bernstein(u);
    final bv = _bernstein(v);
    var x = 0.0, y = 0.0;
    for (var column = 0; column < 4; column++) {
      for (var row = 0; row < 4; row++) {
        final weight = bu[column] * bv[row];
        final point = points[column * 4 + row];
        x += point.x * weight;
        y += point.y * weight;
      }
    }
    return _MeshPoint(x, y);
  }

  List<double> inputs(double u, double v) => <double>[
        for (var component = 0; component < corners[0].length; component++)
          corners[0][component] * (1 - u) * (1 - v) +
              corners[1][component] * (1 - u) * v +
              corners[2][component] * u * v +
              corners[3][component] * u * (1 - v),
      ];

  static List<double> _bernstein(double t) {
    final inverse = 1 - t;
    return <double>[
      inverse * inverse * inverse,
      3 * t * inverse * inverse,
      3 * t * t * inverse,
      t * t * t,
    ];
  }
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

  /// `/BaseFont` de cada fonte desenhada com a tipografia de outra, ordenado.
  ///
  /// O PDF pode referenciar uma fonte sem carregá-la — as catorze padrão, quase
  /// sempre. Quando um substituto é usado, o texto aparece, mas não é o
  /// original: o posicionamento vem do `/Widths` do PDF e os contornos vêm de
  /// outro arquivo, então larguras e desenho pertencem a tipografias
  /// diferentes. Uma página com esta lista não vazia **não** é uma reprodução
  /// fiel, ainda que [isComplete] seja verdadeiro — nada ficou por desenhar,
  /// só não foi desenhado com a fonte certa.
  final List<String> fontsSubstituted;

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
    this.fontsSubstituted = const [],
  });

  bool get isComplete =>
      unsupportedOperators.isEmpty && glyphsSkipped == 0 && imagesSkipped == 0;

  @override
  String toString() => 'PdfRenderReport('
      '${isComplete ? 'complete' : 'partial'}'
      '${unsupportedOperators.isEmpty ? '' : ', unsupported: '
          '${unsupportedOperators.keys.join(' ')}'}'
      '${glyphsSkipped == 0 ? '' : ', $glyphsSkipped text op(s) skipped'}'
      '${imagesSkipped == 0 ? '' : ', $imagesSkipped image(s) skipped'}'
      '${fontsSubstituted.isEmpty ? '' : ', ${fontsSubstituted.length} '
          'font(s) substituted: ${fontsSubstituted.join(' ')}'})';
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
/// text as real glyph outlines — including Type 3 fonts, whose glyphs are
/// content streams the renderer executes (clause 9.6.5).
///
/// Text is drawn from the PDF's own font program when there is one. A document
/// that references a font without carrying it — the standard fourteen, most
/// often — is drawn with the bundled URW faces instead, which are metrically
/// compatible with the fourteen, and [PdfRenderReport.fontsSubstituted] names
/// every font that got that treatment: the widths are the PDF's, the outlines
/// are not. Turn that off with [PdfRenderOptions.useStandardFonts], replace it
/// with [PdfRenderOptions.fontFallback], or add the machine's own catalogue
/// with [PdfRenderOptions.useSystemFonts]. What still cannot be drawn — a
/// composite font, a symbolic one with no bundled equivalent — is measured,
/// positioned and reported through [PdfRenderReport.fontFailures].
///
/// ## Scan conversion, clause 10.6
///
/// Clause 10.6.1 defines pixel coverage by the pixel centre: a shape paints
/// the pixels whose centres fall inside it, all or nothing. This renderer
/// resolves coverage instead, and paints a pixel in proportion to how much of
/// it the shape covers. The divergence is deliberate and it is what every
/// screen renderer does: under the centre rule a table rule thinner than a
/// pixel appears or disappears depending on where it lands, and a curve comes
/// out jagged. Coverage keeps the thin feature, at the weight it really has.
///
/// The cases the clause pins down exactly are followed exactly. A line width
/// of 0 is one device pixel wide at any resolution, not nothing (clause
/// 8.4.3.2). A subpath that never leaves its starting point paints a filled
/// circle of the line width under round caps and nothing at all under butt or
/// projecting square caps, where the cap has no direction (clause 8.5.3.2).
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
        _Renderer(context, base, fontFallback: _substitution(options));
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
        fontsSubstituted:
            List.unmodifiable(renderer.fontsSubstituted.toList()..sort()),
      ),
    );
  }

  /// De onde saem os contornos de uma fonte que o PDF não embutiu.
  ///
  /// Uma fonte fornecida pelo chamador manda sobre tudo. Sem ela, as fontes
  /// do sistema respondem primeiro quando o chamador as pediu, e as URW
  /// embutidas cobrem o resto. Os dois resolvedores são nulos fora do VM, e
  /// aí o texto sem programa segue apenas medido e relatado.
  static PdfFontFallback? _substitution(PdfRenderOptions options) {
    final supplied = options.fontFallback;
    if (supplied != null) return supplied;
    final system = options.useSystemFonts ? systemFontFallback() : null;
    final standard = options.useStandardFonts ? standardFontFallback() : null;
    if (system == null) return standard;
    if (standard == null) return system;
    return (request) async =>
        await system(request) ?? await standard(request);
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

  /// The `/BM` entry of the graphics state, clause 11.3.5.
  _BlendMode blendMode;

  // Text state.
  double fontSize;
  double charSpacing;
  double wordSpacing;
  double horizontalScale;
  double leading;
  double rise;
  int renderMode;

  /// The `/TK` entry of the graphics state, clause 9.3.8. True — the default —
  /// makes all the glyphs of one text object a single knockout element, so
  /// overlapping glyphs do not composite with each other.
  bool textKnockout;

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
    this.blendMode = _BlendMode.normal,
    this.fontSize = 0,
    this.charSpacing = 0,
    this.wordSpacing = 0,
    this.horizontalScale = 1,
    this.leading = 0,
    this.rise = 0,
    this.renderMode = 0,
    this.textKnockout = true,
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
        blendMode: blendMode,
        fontSize: fontSize,
        charSpacing: charSpacing,
        wordSpacing: wordSpacing,
        horizontalScale: horizontalScale,
        leading: leading,
        rise: rise,
        renderMode: renderMode,
        textKnockout: textKnockout,
      );
}

class _Renderer {
  /// Where drawing goes. Not final: compositing an object through a blend
  /// mode, or a transparency group through its group attributes, redirects
  /// the content to an offscreen surface and puts this back afterwards.
  BLContext context;
  final unsupported = <String, int>{};
  var glyphsSkipped = 0;

  /// Por que cada fonte que não pôde ser desenhada foi recusada.
  final fontFailures = <String, PdfGlyphFailure>{};

  /// `/BaseFont` de cada fonte desenhada com o programa de outra.
  final fontsSubstituted = <String>{};
  var imagesSkipped = 0;

  late _State state;
  final _stack = <_State>[];

  /// The path under construction, in device coordinates.
  BLPath _path = BLPath();
  var _pathEmpty = true;
  double _startX = 0, _startY = 0, _currentX = 0, _currentY = 0;

  /// Device-space bounds of [_path], so a blended fill only has to composite
  /// the pixels the path can reach instead of the whole surface.
  double _pathLeft = 0, _pathTop = 0, _pathRight = 0, _pathBottom = 0;

  /// The initial backdrop of the enclosing knockout group, or null when the
  /// current group is not a knockout group (clause 11.4.6). Each object in a
  /// knockout group composites with this rather than with what came before.
  Uint32List? _knockoutBackdrop;

  /// A reusable offscreen surface for blended objects.
  _LayerSurface? _layer;
  var _layerBusy = false;

  /// Glyph outlines accumulated by text rendering modes 4 to 7, in device
  /// space, plus one contour count per contour. Clause 9.3.6: their union is
  /// intersected into the clip when the text object ends.
  List<double>? _textClipVertices;
  List<int>? _textClipContours;

  /// Device-space points of the subpaths that turned out to be degenerate —
  /// a `m` followed by nothing that moved, or only by segments back to the
  /// same coordinates.
  ///
  /// ISO 32000-1 clause 8.5.3.2: `S` paints such a subpath only under round
  /// line caps, as a filled circle of the line width centred on the point.
  /// The rasterizer's stroker cannot produce it — a zero-length segment has
  /// no direction to build a cap on — so the dots are collected here and
  /// filled separately.
  final _degeneratePoints = <double>[];

  /// The start of the subpath under construction, and whether every point
  /// added to it so far has landed on that same spot.
  double _subpathX = 0, _subpathY = 0;
  bool _subpathOpen = false;
  bool _subpathDegenerate = false;

  /// A `W` or `W*` seen before the painting operator that ends the path.
  BLFillRule? _pendingClip;

  /// The text line matrix, in user space: where the current line starts.
  BLMatrix2D _textLineMatrix = BLMatrix2D.identity;

  /// The text matrix. It starts each line as a copy of the line matrix and
  /// then advances glyph by glyph, which is why the two cannot be one field.
  BLMatrix2D _textMatrix = BLMatrix2D.identity;

  /// The font selected by the last `Tf`, resolved to outlines and advances.
  PdfGlyphSource? _font;

  /// True while [_knockoutBackdrop] is the one this renderer took for a text
  /// object under `/TK`, rather than one belonging to a knockout group.
  bool _textKnockoutActive = false;

  /// True while a Type 3 glyph procedure is running, so `d1` only takes
  /// effect where clause 9.6.5 gives it a meaning.
  bool _inType3Glyph = false;

  /// True once the running Type 3 glyph procedure has executed `d1`.
  bool _type3ShapeOnly = false;

  /// The colour operators a `d1` glyph description may not use.
  static const _type3IgnoredOperators = <String>{
    'g', 'G', 'rg', 'RG', 'k', 'K', //
    'cs', 'CS', 'sc', 'scn', 'SC', 'SCN',
  };

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
    if (_type3ShapeOnly && _type3IgnoredOperators.contains(op.operator)) {
      return;
    }
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
        _textClipVertices = null;
        _textClipContours = null;
        _endTextKnockout();
      case 'ET':
        _endTextKnockout();
        await _applyTextClip();
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
        await _showText(op, resources, depth);

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
        break;
      case 'd1':
        // Clause 9.6.5: `d1` declares that the glyph description is a shape
        // only. Everything it paints takes the colour that was in force when
        // the text was shown, so the colour operators inside it are ignored.
        if (_inType3Glyph) _type3ShapeOnly = true;

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

  /// Grows the running device-space bounds of the path under construction.
  void _extend(double x, double y) {
    if (_pathEmpty) {
      _pathLeft = _pathRight = x;
      _pathTop = _pathBottom = y;
      return;
    }
    if (x < _pathLeft) _pathLeft = x;
    if (x > _pathRight) _pathRight = x;
    if (y < _pathTop) _pathTop = y;
    if (y > _pathBottom) _pathBottom = y;
  }

  void _moveTo(double x, double y) {
    final p = _device(x, y);
    _extend(p.$1, p.$2);
    _path.moveTo(p.$1, p.$2);
    _startX = _currentX = p.$1;
    _startY = _currentY = p.$2;
    _pathEmpty = false;
    _closeSubpath();
    _subpathX = p.$1;
    _subpathY = p.$2;
    _subpathOpen = true;
    _subpathDegenerate = true;
  }

  /// Files the subpath just finished, remembering it when it was degenerate.
  void _closeSubpath() {
    if (_subpathOpen && _subpathDegenerate) {
      _degeneratePoints
        ..add(_subpathX)
        ..add(_subpathY);
    }
    _subpathOpen = false;
  }

  /// Notes that the subpath reached [x], [y]; anything away from its start
  /// means it has a direction and is no longer a single point.
  void _subpathReached(double x, double y) {
    if (!_subpathDegenerate) return;
    const epsilon = 1e-9;
    if ((x - _subpathX).abs() > epsilon || (y - _subpathY).abs() > epsilon) {
      _subpathDegenerate = false;
    }
  }

  void _lineTo(double x, double y) {
    if (_pathEmpty) return _moveTo(x, y);
    final p = _device(x, y);
    _extend(p.$1, p.$2);
    _path.lineTo(p.$1, p.$2);
    _subpathReached(p.$1, p.$2);
    _currentX = p.$1;
    _currentY = p.$2;
  }

  void _curveTo(
          double x1, double y1, double x2, double y2, double x3, double y3) =>
      _curveToDevice(_device(x1, y1), _device(x2, y2), _device(x3, y3));

  void _curveToDevice(
      (double, double) c1, (double, double) c2, (double, double) end) {
    if (_pathEmpty) {
      _extend(c1.$1, c1.$2);
      _path.moveTo(c1.$1, c1.$2);
      _startX = _currentX = c1.$1;
      _startY = _currentY = c1.$2;
      _pathEmpty = false;
    }
    // The control hull contains the curve, so its bounds are a safe cover.
    _extend(c1.$1, c1.$2);
    _extend(c2.$1, c2.$2);
    _extend(end.$1, end.$2);
    _path.cubicTo(c1.$1, c1.$2, c2.$1, c2.$2, end.$1, end.$2);
    _subpathReached(c1.$1, c1.$2);
    _subpathReached(c2.$1, c2.$2);
    _subpathReached(end.$1, end.$2);
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
    _closeSubpath();
    if (!_pathEmpty) {
      final path = _path;
      final bounds = _pathBounds;
      if (fill != null) {
        await _paint(
          () async {
            if (state.fillPattern != null) {
              await _fillPattern(path, fill, state.fillPattern!);
            } else {
              await context.fillPath(path,
                  color: _withAlpha(state.fillColour, state.fillAlpha),
                  rule: fill);
            }
          },
          bounds: bounds,
          constantAlpha: state.fillAlpha,
        );
      }
      if (stroke) {
        // A stroke reaches half a line width plus the miter allowance past
        // the path itself, which the fill bounds do not cover.
        final reach =
            (state.lineWidth * _averageScale(state.ctm) * state.miterLimit)
                .ceil()
                .clamp(1, 1 << 20);
        await _paint(
          _strokeCurrentPath,
          bounds: bounds == null
              ? null
              : BLRectI(bounds.x - reach, bounds.y - reach,
                  bounds.width + reach * 2, bounds.height + reach * 2),
          constantAlpha: state.strokeAlpha,
        );
      }
      final clip = _pendingClip;
      if (clip != null) context.clipToPath(path, rule: clip);
    }
    _pendingClip = null;
    _path = BLPath();
    _pathEmpty = true;
    _degeneratePoints.clear();
    _subpathOpen = false;
    _subpathDegenerate = false;
  }

  Future<void> _strokeCurrentPath() async {
    // The path is already in device space, so the line width has to be too.
    // A uniform scale is exact; under a skew this is the average, which is
    // what a stroke of a single width can be.
    final scale = _averageScale(state.ctm);
    await _strokeDegeneratePoints(scale);
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

  /// Paints the dots of clause 8.5.3.2.
  ///
  /// A subpath that never leaves its starting point has no direction, so the
  /// orientation of a butt or projecting-square cap would be indeterminate
  /// and the spec says `S` shall then produce nothing. Round caps are the one
  /// case that is well defined: the two semicircular caps meet and the result
  /// is a filled circle of the line width, centred on the point. Producers
  /// use exactly this to draw a dot — `x y m x y l S` under `1 J`.
  Future<void> _strokeDegeneratePoints(double scale) async {
    if (_degeneratePoints.isEmpty) return;
    if (state.lineCap != BLStrokeCap.round) return;

    // Clause 8.4.3.2: a line width of 0 is the thinnest the device can draw,
    // which is one pixel, so the dot is a one pixel circle rather than none.
    final width = state.lineWidth * scale;
    final radius = (width <= 0 ? 1.0 : width) / 2;

    final dots = BLPath();
    for (var i = 0; i + 1 < _degeneratePoints.length; i += 2) {
      dots.addArc(_degeneratePoints[i], _degeneratePoints[i + 1], radius, 0,
          2 * math.pi);
    }
    final colour = _withAlpha(state.strokeColour, state.strokeAlpha);
    if (state.strokePattern != null) {
      await _fillPattern(dots, BLFillRule.nonZero, state.strokePattern!,
          stroke: true);
      return;
    }
    await context.fillPath(dots, color: colour, rule: BLFillRule.nonZero);
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

  // --- transparency ---------------------------------------------------------

  /// Draws one elementary object, clause 11.3.3.
  ///
  /// With the Normal blend mode outside a knockout group the rasterizer does
  /// the whole job and [body] paints straight onto the surface. Otherwise the
  /// object goes to an offscreen layer first, because both the blend function
  /// and the knockout rule need the object's own colour and alpha separately
  /// from what is already on the page.
  ///
  /// [bounds] limits the compositing pass to the pixels the object can reach;
  /// null means the whole surface. [constantAlpha] is the `ca`/`CA` used to
  /// paint, which is what lets the knockout rule recover the object's shape
  /// from the layer's alpha.
  /// True when knockout compositing can give a different answer from simply
  /// painting each object over the one before.
  ///
  /// With the Normal blend mode, no soft mask and both alpha constants at 1,
  /// an object completely replaces the backdrop wherever its shape is 1, so
  /// compositing it against the group's initial backdrop and against the
  /// accumulated content produce the same pixels. Checking this is what keeps
  /// ordinary opaque text off the offscreen-layer path.
  bool get _knockoutMatters =>
      state.blendMode != _BlendMode.normal ||
      state.fillAlpha < 1 ||
      state.strokeAlpha < 1 ||
      context.opacityMask != null;

  /// Starts treating the glyphs of the current text object as one knockout
  /// element, ISO 32000-1 clause 9.3.8.
  ///
  /// `/TK` defaults to **true**, so this is the normal case: where two glyphs
  /// of the same text object overlap, the later one replaces the earlier
  /// rather than compositing with it, and semi-transparent text does not show
  /// a darker patch at every kerned overlap or accent.
  ///
  /// The snapshot is taken at the first glyph that can actually be affected
  /// rather than at `BT`: copying the whole surface is only worth it when the
  /// result would differ, and glyphs already drawn opaquely would knock
  /// themselves out to the same pixels anyway.
  void _beginTextKnockout() {
    if (_knockoutBackdrop != null) return; // Already inside a knockout group.
    if (!state.textKnockout) return;
    if (!_knockoutMatters) return;
    _knockoutBackdrop = Uint32List.fromList(context.image.pixels);
    _textKnockoutActive = true;
  }

  void _endTextKnockout() {
    if (!_textKnockoutActive) return;
    _textKnockoutActive = false;
    _knockoutBackdrop = null;
  }

  Future<void> _paint(
    Future<void> Function() body, {
    BLRectI? bounds,
    double constantAlpha = 1,
  }) async {
    final mode = state.blendMode;
    final knockout = _knockoutBackdrop;
    if (mode == _BlendMode.normal && knockout == null) {
      await body();
      return;
    }

    final target = context;
    final rect = _clampToSurface(bounds, target.image);
    if (rect == null) return;

    final reused = !_layerBusy;
    final layer = reused
        ? _borrowLayer(target)
        : _LayerSurface(BLImage(target.image.width, target.image.height));
    if (!reused) _configureLayer(layer, target);
    _layerBusy = true;
    _clearRegion(layer.image, rect);

    context = layer.context;
    try {
      await body();
    } finally {
      context = target;
      layer.context.flush();
      if (reused) _layerBusy = false;
    }

    _composeObject(target, layer.image, rect,
        mode: mode, knockout: knockout, constantAlpha: constantAlpha);
  }

  _LayerSurface _borrowLayer(BLContext target) {
    var layer = _layer;
    if (layer == null ||
        layer.image.width != target.image.width ||
        layer.image.height != target.image.height) {
      layer = _LayerSurface(BLImage(target.image.width, target.image.height));
      _layer = layer;
    }
    _configureLayer(layer, target);
    return layer;
  }

  /// Gives [layer] the same clip and soft mask as [target].
  ///
  /// Both are compared by identity: [BLContext] publishes a new mask whenever
  /// the clip changes, so an unchanged reference means an unchanged clip and
  /// the copy can be skipped.
  static void _configureLayer(_LayerSurface layer, BLContext target) {
    final rect = target.clipRect;
    if (layer.configured &&
        identical(layer.clipMask, target.clipMask) &&
        identical(layer.opacityMask, target.opacityMask) &&
        _sameRect(layer.clipRect, rect)) {
      return;
    }
    layer.context.resetClip();
    layer.context.setClipRect(rect);
    final mask = target.clipMask;
    if (mask != null) layer.context.intersectClipMask(mask);
    layer.context.setOpacityMask(target.opacityMask);
    layer.clipMask = mask;
    layer.opacityMask = target.opacityMask;
    layer.clipRect = rect;
    layer.configured = true;
  }

  static bool _sameRect(BLRectI? a, BLRectI? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.x == b.x &&
        a.y == b.y &&
        a.width == b.width &&
        a.height == b.height;
  }

  static BLRectI? _clampToSurface(BLRectI? bounds, BLImage image) {
    if (bounds == null) return BLRectI(0, 0, image.width, image.height);
    final x0 = math.max(0, bounds.x);
    final y0 = math.max(0, bounds.y);
    final x1 = math.min(image.width, bounds.x + bounds.width);
    final y1 = math.min(image.height, bounds.y + bounds.height);
    if (x1 <= x0 || y1 <= y0) return null;
    return BLRectI(x0, y0, x1 - x0, y1 - y0);
  }

  /// Device bounds of a rectangle whose corners are [points], padded by one
  /// pixel so antialiased edges are not clipped away.
  static BLRectI _boundsOf(List<(double, double)> points) {
    var left = points.first.$1, right = left;
    var top = points.first.$2, bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.$1);
      right = math.max(right, point.$1);
      top = math.min(top, point.$2);
      bottom = math.max(bottom, point.$2);
    }
    final x = left.floor() - 1;
    final y = top.floor() - 1;
    return BLRectI(x, y, right.ceil() + 1 - x, bottom.ceil() + 1 - y);
  }

  BLRectI? get _pathBounds => _pathEmpty
      ? null
      : _boundsOf([(_pathLeft, _pathTop), (_pathRight, _pathBottom)]);

  static void _clearRegion(BLImage image, BLRectI rect) {
    final pixels = image.pixels;
    if (rect.x == 0 && rect.width == image.width) {
      pixels.fillRange(
          rect.y * image.width, (rect.y + rect.height) * image.width, 0);
      return;
    }
    for (var y = rect.y; y < rect.y + rect.height; y++) {
      final row = y * image.width;
      pixels.fillRange(row + rect.x, row + rect.x + rect.width, 0);
    }
  }

  /// Composites an object rendered into [source] onto [target].
  void _composeObject(
    BLContext target,
    BLImage source,
    BLRectI rect, {
    required _BlendMode mode,
    required Uint32List? knockout,
    required double constantAlpha,
  }) {
    final destination = target.image.pixels;
    final layer = source.pixels;
    final opacity = target.opacityMask;
    final width = target.image.width;
    final backdrop = List<double>.filled(3, 0);
    final colour = List<double>.filled(3, 0);
    final blended = List<double>.filled(3, 0);

    for (var y = rect.y; y < rect.y + rect.height; y++) {
      final row = y * width;
      for (var x = rect.x; x < rect.x + rect.width; x++) {
        final index = row + x;
        final src = layer[index];
        final sourceAlpha = (src >>> 24) & 0xff;
        if (sourceAlpha == 0) continue;

        if (knockout == null) {
          destination[index] = _composite(destination[index], src,
              sourceAlpha / 255, mode, backdrop, colour, blended);
          continue;
        }

        // Clause 11.4.6: the object composites with the group's initial
        // backdrop using a source shape of 1.0, and that result then replaces
        // the accumulated group content in proportion to the object's shape.
        // The layer's alpha is shape times opacity, so dividing by the
        // constant alpha that painted it recovers the shape.
        var opacityFactor = constantAlpha;
        if (opacity != null) opacityFactor *= opacity[index] / 255;
        if (opacityFactor <= 0) continue;
        final shape = math.min(1.0, (sourceAlpha / 255) / opacityFactor);
        if (shape <= 0) continue;
        final composed = _composite(knockout[index], src, opacityFactor, mode,
            backdrop, colour, blended);
        destination[index] = _mix(destination[index], composed, shape);
      }
    }
  }

  /// The colour and alpha compositing formulas of clauses 11.3.6 and 11.3.7,
  /// for one source pixel over one backdrop pixel.
  static int _composite(
    int backdropPixel,
    int sourcePixel,
    double sourceAlpha,
    _BlendMode mode,
    List<double> backdrop,
    List<double> colour,
    List<double> blended,
  ) {
    if (sourceAlpha <= 0) return backdropPixel;
    final ab = ((backdropPixel >>> 24) & 0xff) / 255;
    final as = sourceAlpha.clamp(0.0, 1.0);
    final ar = ab + as - ab * as;
    if (ar <= 0) return 0;

    backdrop[0] = ((backdropPixel >>> 16) & 0xff) / 255;
    backdrop[1] = ((backdropPixel >>> 8) & 0xff) / 255;
    backdrop[2] = (backdropPixel & 0xff) / 255;
    colour[0] = ((sourcePixel >>> 16) & 0xff) / 255;
    colour[1] = ((sourcePixel >>> 8) & 0xff) / 255;
    colour[2] = (sourcePixel & 0xff) / 255;

    if (mode.isSeparable) {
      for (var i = 0; i < 3; i++) {
        blended[i] = mode.blendChannel(backdrop[i], colour[i]);
      }
    } else {
      mode.blendColour(backdrop, colour, blended);
    }

    final weight = as / ar;
    var result = (ar * 255).round().clamp(0, 255) << 24;
    for (var i = 0; i < 3; i++) {
      final mixed = (1 - ab) * colour[i] + ab * blended[i];
      final value = (1 - weight) * backdrop[i] + weight * mixed;
      result |= (value.clamp(0.0, 1.0) * 255).round() << (16 - i * 8);
    }
    return result;
  }

  /// A weighted average of two straight-alpha pixels, done on premultiplied
  /// values so a transparent pixel contributes no colour.
  static int _mix(int a, int b, double weight) {
    if (weight >= 1) return b;
    if (weight <= 0) return a;
    final aa = (a >>> 24) & 0xff;
    final ba = (b >>> 24) & 0xff;
    final alpha = aa * (1 - weight) + ba * weight;
    if (alpha <= 0) return 0;
    var result = alpha.round().clamp(0, 255) << 24;
    for (var shift = 16; shift >= 0; shift -= 8) {
      final value = ((a >>> shift) & 0xff) * aa * (1 - weight) +
          ((b >>> shift) & 0xff) * ba * weight;
      result |= (value / alpha).round().clamp(0, 255) << shift;
    }
    return result;
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
    await _paint(
      () => _fillShadingPattern(surface, BLFillRule.nonZero, pattern,
          stroke: false),
      constantAlpha: state.fillAlpha,
    );
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
    fontsSubstituted.addAll(nested.fontsSubstituted);

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

  /// Paints a shading, honouring the `/BBox` every shading dictionary may
  /// carry (Table 78): a clip, expressed in the shading's target space.
  Future<void> _fillShadingPattern(
      BLPath path, BLFillRule rule, PdfDictionary pattern,
      {required bool stroke}) async {
    final shadingObject = await pattern.get(PdfName.shading, true);
    if (shadingObject is! PdfDictionary) {
      _note('scn:malformed-shading-pattern');
      return;
    }
    final bbox = await shadingObject.arrayEntry(PdfName.bBox);
    if (bbox == null || bbox.size() != 4) {
      await _fillShadingPatternInner(path, rule, pattern, shadingObject,
          stroke: stroke);
      return;
    }
    final b = await bbox.toDoubleArray();
    final toDevice = (await _patternMatrix(pattern)).multiply(state.ctm);
    final x0 = math.min(b[0], b[2]);
    final y0 = math.min(b[1], b[3]);
    final x1 = math.max(b[0], b[2]);
    final y1 = math.max(b[1], b[3]);
    context.save();
    context.clipToPath(_polygon(<(double, double)>[
      toDevice.mapPoint(x0, y0),
      toDevice.mapPoint(x1, y0),
      toDevice.mapPoint(x1, y1),
      toDevice.mapPoint(x0, y1),
    ]));
    try {
      await _fillShadingPatternInner(path, rule, pattern, shadingObject,
          stroke: stroke);
    } finally {
      context.restore();
    }
  }

  /// The pattern's `/Matrix`, or the identity when it has none.
  Future<BLMatrix2D> _patternMatrix(PdfDictionary pattern) async {
    final array = await pattern.arrayEntry(PdfName.matrix);
    if (array == null || array.size() != 6) return BLMatrix2D.identity;
    final m = await array.toDoubleArray();
    return BLMatrix2D(m[0], m[1], m[2], m[3], m[4], m[5]);
  }

  Future<void> _fillShadingPatternInner(BLPath path, BLFillRule rule,
      PdfDictionary pattern, PdfDictionary shadingObject,
      {required bool stroke}) async {
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
    if (shadingType == 1 && colorSpace != null) {
      if (await _fillFunctionShading(path, rule, pattern, shading, colorSpace,
          stroke: stroke)) {
        return;
      }
      _note('scn:unsupported-shading-pattern');
      return;
    }
    if (shadingType == 4 && shading is PdfStream && colorSpace != null) {
      if (await _fillFreeFormShading(
          path, rule, pattern, shading, colorSpace, function,
          stroke: stroke)) {
        return;
      }
      _note('scn:unsupported-shading-pattern');
      return;
    }
    if (shadingType == 5 && shading is PdfStream && colorSpace != null) {
      if (await _fillLatticeShading(
          path, rule, pattern, shading, colorSpace, function,
          stroke: stroke)) {
        return;
      }
      _note('scn:unsupported-shading-pattern');
      return;
    }
    if ((shadingType == 6 || shadingType == 7) &&
        shading is PdfStream &&
        colorSpace != null) {
      if (await _fillPatchShading(
          path, rule, pattern, shading, colorSpace, function,
          coons: shadingType == 6, stroke: stroke)) {
        return;
      }
      _note('scn:unsupported-shading-pattern');
      return;
    }
    if (expectedCoords == 0 ||
        coordsArray == null ||
        coordsArray.size() != expectedCoords ||
        function == null ||
        colorSpace == null) {
      _note('scn:unsupported-shading-pattern');
      return;
    }
    final coords = await coordsArray.toDoubleArray();
    var extendStart = false;
    var extendEnd = false;
    final extend = await shading.arrayEntry(PdfName('Extend'));
    if (extend != null && extend.size() == 2) {
      extendStart = (await extend.booleanEntry(0))?.getValue() ?? false;
      extendEnd = (await extend.booleanEntry(1))?.getValue() ?? false;
    }
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
          p0: BLPoint(p0.$1, p0.$2),
          p1: BLPoint(p1.$1, p1.$2),
          stops: stops,
          extendStart: extendStart,
          extendEnd: extendEnd));
    } else {
      final c0 = toDevice.mapPoint(coords[0], coords[1]);
      final c1 = toDevice.mapPoint(coords[3], coords[4]);
      final scale = _averageScale(toDevice);
      context.setRadialGradient(BLRadialGradient(
          c0: BLPoint(c0.$1, c0.$2),
          c1: BLPoint(c1.$1, c1.$2),
          r0: coords[2] * scale,
          r1: coords[5] * scale,
          stops: stops,
          extendStart: extendStart,
          extendEnd: extendEnd));
    }
    await context.fillPath(path, rule: rule);
    context.setFillStyle(stroke ? state.strokeColour : state.fillColour);
  }

  /// ShadingType 1, clause 8.7.4.5.2: the colour at a point is whatever the
  /// shading's function says it is, over a rectangular domain that `/Matrix`
  /// places in the pattern's space.
  Future<bool> _fillFunctionShading(
    BLPath clipPath,
    BLFillRule rule,
    PdfDictionary pattern,
    PdfDictionary shading,
    PdfColorSpace colorSpace, {
    required bool stroke,
  }) async {
    final evaluate =
        await _surfaceFunction(await shading.get(PdfName.function, true));
    if (evaluate == null) return false;

    var domain = <double>[0, 1, 0, 1];
    final domainArray = await shading.arrayEntry(PdfName('Domain'));
    if (domainArray != null && domainArray.size() == 4) {
      domain = await domainArray.toDoubleArray();
    }
    if (!(domain[1] > domain[0]) || !(domain[3] > domain[2])) return false;

    var matrix = BLMatrix2D.identity;
    final matrixArray = await shading.arrayEntry(PdfName.matrix);
    if (matrixArray != null && matrixArray.size() == 6) {
      final m = await matrixArray.toDoubleArray();
      matrix = BLMatrix2D(m[0], m[1], m[2], m[3], m[4], m[5]);
    }
    final toDevice =
        matrix.multiply((await _patternMatrix(pattern)).multiply(state.ctm));
    final fromDevice = toDevice.invert();
    if (fromDevice == null) return false;

    // Points outside the transformed domain take the shading's /Background
    // when it has one, and stay unpainted when it does not.
    int background = 0x00000000;
    final backgroundArray = await shading.arrayEntry(PdfName('Background'));
    if (backgroundArray != null &&
        backgroundArray.size() == colorSpace.getNumberOfComponents()) {
      try {
        final rgb = colorSpace.toRgb(await backgroundArray.toDoubleArray());
        background = _rgb(rgb[0], rgb[1], rgb[2]);
      } on Object {
        background = 0x00000000;
      }
    }

    final region =
        _clampToSurface(_boundsOf(_pathCorners(clipPath)), context.image);
    if (region == null) return true;

    final alpha =
        ((stroke ? state.strokeAlpha : state.fillAlpha).clamp(0.0, 1.0) * 255)
            .round();
    final surface = BLImage(region.width, region.height);
    final pixels = surface.pixels;
    final cache = <int, int>{};
    for (var y = 0; y < region.height; y++) {
      final row = y * region.width;
      for (var x = 0; x < region.width; x++) {
        // Sample at the pixel centre, which is where the rasterizer decides
        // coverage from.
        final point =
            fromDevice.mapPoint(region.x + x + 0.5, region.y + y + 0.5);
        if (point.$1 < domain[0] ||
            point.$1 > domain[1] ||
            point.$2 < domain[2] ||
            point.$2 > domain[3]) {
          pixels[row + x] =
              background == 0 ? 0 : _withAlphaByte(background, alpha);
          continue;
        }
        // Function evaluation dominates the cost here, and a smooth shading
        // repeats colours constantly; quantising the domain to a fine grid
        // makes the cache hit almost always without a visible difference.
        final key = ((point.$1 - domain[0]) / (domain[1] - domain[0]) * 1023)
                    .round()
                    .clamp(0, 1023) *
                1024 +
            ((point.$2 - domain[2]) / (domain[3] - domain[2]) * 1023)
                .round()
                .clamp(0, 1023);
        var colour = cache[key];
        if (colour == null) {
          try {
            final rgb = colorSpace.toRgb(evaluate(point.$1, point.$2));
            colour = _withAlphaByte(_rgb(rgb[0], rgb[1], rgb[2]), alpha);
          } on Object {
            colour = 0;
          }
          cache[key] = colour;
        }
        pixels[row + x] = colour;
      }
    }

    context.setPattern(BLPattern(
      image: surface,
      transform:
          BLMatrix2D(1, 0, 0, 1, -region.x.toDouble(), -region.y.toDouble()),
    ));
    await context.fillPath(clipPath, rule: rule);
    context.setFillStyle(stroke ? state.strokeColour : state.fillColour);
    return true;
  }

  static int _withAlphaByte(int colour, int alpha) =>
      (colour & 0x00FFFFFF) | (alpha.clamp(0, 255) << 24);

  static List<(double, double)> _pathCorners(BLPath path) {
    final data = path.toPathData();
    if (data.vertices.isEmpty) return const [(0.0, 0.0)];
    var left = data.vertices[0], right = left;
    var top = data.vertices[1], bottom = top;
    for (var i = 2; i < data.vertices.length; i += 2) {
      left = math.min(left, data.vertices[i]);
      right = math.max(right, data.vertices[i]);
      top = math.min(top, data.vertices[i + 1]);
      bottom = math.max(bottom, data.vertices[i + 1]);
    }
    return <(double, double)>[(left, top), (right, bottom)];
  }

  /// A 2-in n-out function, which `/Function` may also express as n separate
  /// 2-in 1-out functions (clause 8.7.4.5.2).
  Future<List<double> Function(double, double)?> _surfaceFunction(
      PdfObject? object) async {
    if (object is PdfArray) {
      final parts = <PdfFunction>[];
      for (var i = 0; i < object.size(); i++) {
        final part = await PdfFunction.parse(await object.get(i));
        if (part == null || part.inputCount != 2 || part.outputCount != 1) {
          return null;
        }
        parts.add(part);
      }
      if (parts.isEmpty) return null;
      return (x, y) => <double>[
            for (final part in parts) part.evaluate(<double>[x, y]).first
          ];
    }
    final function = await PdfFunction.parse(object);
    if (function == null || function.inputCount != 2) return null;
    return (x, y) => function.evaluate(<double>[x, y]);
  }

  Future<bool> _fillPatchShading(
    BLPath clipPath,
    BLFillRule rule,
    PdfDictionary pattern,
    PdfStream shading,
    PdfColorSpace colorSpace,
    PdfFunction? function, {
    required bool coons,
    required bool stroke,
  }) async {
    final bitsCoordinate =
        await shading.integerEntry(PdfName('BitsPerCoordinate'));
    final bitsComponent =
        await shading.integerEntry(PdfName('BitsPerComponent'));
    final bitsFlag = await shading.integerEntry(PdfName('BitsPerFlag'));
    final decodeArray = await shading.arrayEntry(PdfName('Decode'));
    final inputCount =
        function?.inputCount ?? colorSpace.getNumberOfComponents();
    if (bitsCoordinate == null ||
        bitsComponent == null ||
        bitsFlag == null ||
        bitsCoordinate < 1 ||
        bitsCoordinate > 32 ||
        bitsComponent < 1 ||
        bitsComponent > 16 ||
        (bitsFlag != 2 && bitsFlag != 4 && bitsFlag != 8) ||
        inputCount < 1 ||
        decodeArray == null ||
        decodeArray.size() != 4 + inputCount * 2) {
      return false;
    }
    final decode = await decodeArray.toDoubleArray();
    final bytes = await shading.getBytes();
    if (bytes == null) return false;
    final reader = _MeshBitReader(bytes);
    final coordinateMax = (1 << bitsCoordinate) - 1;
    final componentMax = (1 << bitsComponent) - 1;
    const streamOrder = <int>[
      0,
      1,
      2,
      3,
      7,
      11,
      15,
      14,
      13,
      12,
      8,
      4,
      5,
      6,
      10,
      9
    ];
    final patches = <_TensorPatch>[];
    _TensorPatch? previous;
    try {
      while (reader.remaining >= bitsFlag && patches.length < 10000) {
        final flag = reader.read(bitsFlag);
        if (flag < 0 || flag > 3 || (flag != 0 && previous == null)) {
          return false;
        }
        final pointCount = flag == 0 ? (coons ? 12 : 16) : (coons ? 8 : 12);
        final colourCount = flag == 0 ? 4 : 2;
        final payloadBits = pointCount * 2 * bitsCoordinate +
            colourCount * inputCount * bitsComponent;
        if (reader.remaining < payloadBits) {
          // At most seven zero padding bits may close the stream.
          if (patches.isNotEmpty && reader.remaining < 8) {
            reader.bitOffset = bytes.length * 8;
            break;
          }
          return false;
        }
        final points = List<_MeshPoint?>.filled(16, null);
        final corners = List<List<double>?>.filled(4, null);
        var orderOffset = 0;
        if (flag != 0) {
          final inheritedPoints = switch (flag) {
            1 => <int>[3, 7, 11, 15],
            2 => <int>[15, 14, 13, 12],
            _ => <int>[12, 8, 4, 0],
          };
          for (var index = 0; index < 4; index++) {
            points[streamOrder[index]] =
                previous!.points[inheritedPoints[index]];
          }
          final inheritedColours = switch (flag) {
            1 => <int>[1, 2],
            2 => <int>[2, 3],
            _ => <int>[3, 0],
          };
          corners[0] = previous!.corners[inheritedColours[0]];
          corners[1] = previous.corners[inheritedColours[1]];
          orderOffset = 4;
        }
        for (var index = 0; index < pointCount; index++) {
          final x = _meshDecode(
              reader.read(bitsCoordinate), coordinateMax, decode[0], decode[1]);
          final y = _meshDecode(
              reader.read(bitsCoordinate), coordinateMax, decode[2], decode[3]);
          points[streamOrder[orderOffset + index]] = _MeshPoint(x, y);
        }
        final colourOffset = flag == 0 ? 0 : 2;
        for (var corner = 0; corner < colourCount; corner++) {
          corners[colourOffset + corner] = <double>[
            for (var component = 0; component < inputCount; component++)
              _meshDecode(reader.read(bitsComponent), componentMax,
                  decode[4 + component * 2], decode[5 + component * 2]),
          ];
        }
        if (coons) {
          _completeCoonsControls(points);
        }
        if (points.any((point) => point == null) ||
            corners.any((colour) => colour == null)) {
          return false;
        }
        previous = _TensorPatch(
            points.cast<_MeshPoint>(), corners.cast<List<double>>());
        patches.add(previous);
      }
    } on Object {
      return false;
    }
    if (reader.remaining >= bitsFlag || patches.isEmpty) return false;

    var matrix = BLMatrix2D.identity;
    final matrixArray = await pattern.arrayEntry(PdfName.matrix);
    if (matrixArray != null && matrixArray.size() == 6) {
      final values = await matrixArray.toDoubleArray();
      matrix = BLMatrix2D(
          values[0], values[1], values[2], values[3], values[4], values[5]);
    }
    final toDevice = matrix.multiply(state.ctm);
    final alpha = stroke ? state.strokeAlpha : state.fillAlpha;
    context.save();
    context.clipToPath(clipPath, rule: rule);
    try {
      // Every patch of the shading goes into one mesh. Adjacent patches share
      // an edge exactly — flags 1 to 3 inherit the neighbour's control points
      // — so painting them together is what keeps the join seamless too.
      final mesh = _MeshAccumulator();
      for (final patch in patches) {
        _tessellateTensorPatch(
            patch, toDevice, colorSpace, function, alpha, mesh);
      }
      await mesh.paint(context);
    } finally {
      context.restore();
      context.setFillStyle(stroke ? state.strokeColour : state.fillColour);
    }
    return true;
  }

  void _completeCoonsControls(List<_MeshPoint?> points) {
    _MeshPoint weighted(List<(int, double)> terms) {
      var x = 0.0, y = 0.0;
      for (final (index, weight) in terms) {
        final point = points[index]!;
        x += point.x * weight;
        y += point.y * weight;
      }
      return _MeshPoint(x / 9, y / 9);
    }

    // PDF Coons patches omit the four interior controls. Convert their
    // boundary curves to the equivalent bicubic tensor-product patch.
    points[5] = weighted(const [
      (0, -4),
      (1, 6),
      (4, 6),
      (3, -2),
      (12, -2),
      (13, 3),
      (7, 3),
      (15, -1),
    ]);
    points[6] = weighted(const [
      (3, -4),
      (2, 6),
      (7, 6),
      (0, -2),
      (15, -2),
      (14, 3),
      (4, 3),
      (12, -1),
    ]);
    points[9] = weighted(const [
      (12, -4),
      (13, 6),
      (8, 6),
      (15, -2),
      (0, -2),
      (1, 3),
      (11, 3),
      (3, -1),
    ]);
    points[10] = weighted(const [
      (15, -4),
      (14, 6),
      (11, 6),
      (12, -2),
      (3, -2),
      (2, 3),
      (8, 3),
      (0, -1),
    ]);
  }

  /// Splits one Coons or tensor patch into a triangle grid and adds it to
  /// [mesh].
  ///
  /// The colour of a grid vertex is the function evaluated at that vertex's
  /// own parametric inputs, so the non-linearity of the function is carried
  /// by the grid; interpolating colour between two grid vertices is what
  /// clause 8.7.4.5.7 asks for.
  void _tessellateTensorPatch(
      _TensorPatch patch,
      BLMatrix2D toDevice,
      PdfColorSpace colorSpace,
      PdfFunction? function,
      double alpha,
      _MeshAccumulator mesh) {
    final transformedControls =
        patch.points.map((point) => point.transform(toDevice)).toList();
    var left = transformedControls.first.x;
    var right = left;
    var top = transformedControls.first.y;
    var bottom = top;
    for (final point in transformedControls.skip(1)) {
      left = math.min(left, point.x);
      right = math.max(right, point.x);
      top = math.min(top, point.y);
      bottom = math.max(bottom, point.y);
    }
    final divisions =
        (math.max(right - left, bottom - top) / 4).ceil().clamp(2, 24);
    final grid = List<List<_MeshVertex>>.generate(divisions + 1, (uIndex) {
      final u = uIndex / divisions;
      return List<_MeshVertex>.generate(divisions + 1, (vIndex) {
        final v = vIndex / divisions;
        final point = patch.evaluate(u, v).transform(toDevice);
        final inputs = patch.inputs(u, v);
        final components = function?.evaluate(inputs) ?? inputs;
        final rgb = colorSpace.toRgb(components);
        return _MeshVertex(point.x, point.y, rgb[0], rgb[1], rgb[2]);
      });
    });
    for (var u = 0; u < divisions; u++) {
      for (var v = 0; v < divisions; v++) {
        mesh.addTriangle(grid[u][v], grid[u + 1][v], grid[u][v + 1], alpha);
        mesh.addTriangle(
            grid[u + 1][v], grid[u + 1][v + 1], grid[u][v + 1], alpha);
      }
    }
  }

  Future<bool> _fillFreeFormShading(
    BLPath clipPath,
    BLFillRule rule,
    PdfDictionary pattern,
    PdfStream shading,
    PdfColorSpace colorSpace,
    PdfFunction? function, {
    required bool stroke,
  }) async {
    final bitsCoordinate =
        await shading.integerEntry(PdfName('BitsPerCoordinate'));
    final bitsComponent =
        await shading.integerEntry(PdfName('BitsPerComponent'));
    final bitsFlag = await shading.integerEntry(PdfName('BitsPerFlag'));
    final decodeArray = await shading.arrayEntry(PdfName('Decode'));
    final inputCount =
        function?.inputCount ?? colorSpace.getNumberOfComponents();
    if (bitsCoordinate == null ||
        bitsComponent == null ||
        bitsFlag == null ||
        bitsCoordinate < 1 ||
        bitsCoordinate > 32 ||
        bitsComponent < 1 ||
        bitsComponent > 16 ||
        (bitsFlag != 2 && bitsFlag != 4 && bitsFlag != 8) ||
        inputCount < 1 ||
        decodeArray == null ||
        decodeArray.size() != 4 + inputCount * 2) {
      return false;
    }
    final decode = await decodeArray.toDoubleArray();
    final bytes = await shading.getBytes();
    if (bytes == null) return false;
    final reader = _MeshBitReader(bytes);
    final bitsPerRecord =
        bitsFlag + bitsCoordinate * 2 + bitsComponent * inputCount;
    final coordinateMax = (1 << bitsCoordinate) - 1;
    final componentMax = (1 << bitsComponent) - 1;
    final records = <({int flag, _MeshVertex vertex})>[];
    try {
      while (reader.remaining >= bitsPerRecord && records.length < 100000) {
        final flag = reader.read(bitsFlag);
        final x = _meshDecode(
            reader.read(bitsCoordinate), coordinateMax, decode[0], decode[1]);
        final y = _meshDecode(
            reader.read(bitsCoordinate), coordinateMax, decode[2], decode[3]);
        final inputs = <double>[];
        for (var i = 0; i < inputCount; i++) {
          inputs.add(_meshDecode(reader.read(bitsComponent), componentMax,
              decode[4 + i * 2], decode[5 + i * 2]));
        }
        final components = function?.evaluate(inputs) ?? inputs;
        final rgb = colorSpace.toRgb(components);
        records.add((
          flag: flag,
          vertex: _MeshVertex(
              x, y, rgb[0], rgb[1], rgb[2], function == null ? null : inputs),
        ));
      }
    } on Object {
      return false;
    }
    if (reader.remaining >= bitsPerRecord || records.length < 3) return false;
    final triangles = <List<_MeshVertex>>[];
    List<_MeshVertex>? previous;
    for (var index = 0; index < records.length;) {
      final record = records[index];
      late final List<_MeshVertex> triangle;
      if (record.flag == 0) {
        if (index + 2 >= records.length) return false;
        triangle = <_MeshVertex>[
          record.vertex,
          records[index + 1].vertex,
          records[index + 2].vertex,
        ];
        index += 3;
      } else if (record.flag == 1 && previous != null) {
        triangle = <_MeshVertex>[previous[1], previous[2], record.vertex];
        index++;
      } else if (record.flag == 2 && previous != null) {
        triangle = <_MeshVertex>[previous[0], previous[2], record.vertex];
        index++;
      } else {
        return false;
      }
      triangles.add(triangle);
      previous = triangle;
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
    context.save();
    context.clipToPath(clipPath, rule: rule);
    try {
      // One device-space vertex per record: triangles joined by a flag 1 or 2
      // share vertex objects, and the mesh needs the shared corners to land
      // on the very same coordinates for its interior edges to cancel.
      final devices = Map<_MeshVertex, _MeshVertex>.identity();
      _MeshVertex device(_MeshVertex vertex) =>
          devices[vertex] ??= vertex.transform(toDevice);
      final mesh = _MeshAccumulator();
      for (final triangle in triangles) {
        final a = device(triangle[0]);
        final b = device(triangle[1]);
        final c = device(triangle[2]);
        if (function == null) {
          mesh.addTriangle(a, b, c, alpha);
        } else {
          // A parametric mesh carries one value of t per vertex and takes its
          // colour from the function. Interpolating the colour would be
          // interpolating after the function instead of before it, which is a
          // different picture for every function that is not affine, so the
          // triangle is subdivided and the function sampled per facet.
          _tessellateParametricTriangle(
              a, b, c, alpha, function, colorSpace, mesh);
        }
      }
      await mesh.paint(context);
    } finally {
      context.restore();
      context.setFillStyle(stroke ? state.strokeColour : state.fillColour);
    }
    return true;
  }

  Future<bool> _fillLatticeShading(
    BLPath clipPath,
    BLFillRule rule,
    PdfDictionary pattern,
    PdfStream shading,
    PdfColorSpace colorSpace,
    PdfFunction? function, {
    required bool stroke,
  }) async {
    final bitsCoordinate =
        await shading.integerEntry(PdfName('BitsPerCoordinate'));
    final bitsComponent =
        await shading.integerEntry(PdfName('BitsPerComponent'));
    final verticesPerRow =
        await shading.integerEntry(PdfName('VerticesPerRow'));
    final decodeArray = await shading.arrayEntry(PdfName('Decode'));
    final inputCount =
        function?.inputCount ?? colorSpace.getNumberOfComponents();
    if (bitsCoordinate == null ||
        bitsComponent == null ||
        verticesPerRow == null ||
        bitsCoordinate < 1 ||
        bitsCoordinate > 32 ||
        bitsComponent < 1 ||
        bitsComponent > 16 ||
        verticesPerRow < 2 ||
        inputCount < 1 ||
        decodeArray == null ||
        decodeArray.size() != 4 + inputCount * 2) {
      return false;
    }
    final decode = await decodeArray.toDoubleArray();
    final bytes = await shading.getBytes();
    if (bytes == null) return false;
    final reader = _MeshBitReader(bytes);
    final bitsPerVertex = bitsCoordinate * 2 + bitsComponent * inputCount;
    final vertices = <_MeshVertex>[];
    final coordinateMax = (1 << bitsCoordinate) - 1;
    final componentMax = (1 << bitsComponent) - 1;
    while (reader.remaining >= bitsPerVertex && vertices.length < 100000) {
      final x = _meshDecode(
          reader.read(bitsCoordinate), coordinateMax, decode[0], decode[1]);
      final y = _meshDecode(
          reader.read(bitsCoordinate), coordinateMax, decode[2], decode[3]);
      final inputs = <double>[];
      for (var i = 0; i < inputCount; i++) {
        inputs.add(_meshDecode(reader.read(bitsComponent), componentMax,
            decode[4 + i * 2], decode[5 + i * 2]));
      }
      final components = function?.evaluate(inputs) ?? inputs;
      final rgb = colorSpace.toRgb(components);
      vertices.add(_MeshVertex(
          x, y, rgb[0], rgb[1], rgb[2], function == null ? null : inputs));
    }
    if (reader.remaining >= bitsPerVertex) return false;
    if (vertices.length < verticesPerRow * 2 ||
        vertices.length % verticesPerRow != 0) {
      return false;
    }
    var matrix = BLMatrix2D.identity;
    final matrixArray = await pattern.arrayEntry(PdfName.matrix);
    if (matrixArray != null && matrixArray.size() == 6) {
      final values = await matrixArray.toDoubleArray();
      matrix = BLMatrix2D(
          values[0], values[1], values[2], values[3], values[4], values[5]);
    }
    final toDevice = matrix.multiply(state.ctm);
    final transformed = <_MeshVertex>[
      for (final vertex in vertices) vertex.transform(toDevice)
    ];
    final alpha = stroke ? state.strokeAlpha : state.fillAlpha;
    context.save();
    context.clipToPath(clipPath, rule: rule);
    try {
      final rows = transformed.length ~/ verticesPerRow;
      // Without a function the vertex colours are already device RGB, so the
      // whole lattice is one Gouraud mesh. With one, see the note in
      // [_fillFreeFormShading]: t is interpolated, not the colour.
      final mesh = _MeshAccumulator();
      for (var row = 0; row + 1 < rows; row++) {
        for (var column = 0; column + 1 < verticesPerRow; column++) {
          final topLeft = transformed[row * verticesPerRow + column];
          final topRight = transformed[row * verticesPerRow + column + 1];
          final bottomLeft = transformed[(row + 1) * verticesPerRow + column];
          final bottomRight =
              transformed[(row + 1) * verticesPerRow + column + 1];
          if (function == null) {
            mesh.addTriangle(topLeft, topRight, bottomLeft, alpha);
            mesh.addTriangle(topRight, bottomRight, bottomLeft, alpha);
          } else {
            _tessellateParametricTriangle(topLeft, topRight, bottomLeft, alpha,
                function, colorSpace, mesh);
            _tessellateParametricTriangle(topRight, bottomRight, bottomLeft,
                alpha, function, colorSpace, mesh);
          }
        }
      }
      await mesh.paint(context);
    } finally {
      context.restore();
      context.setFillStyle(stroke ? state.strokeColour : state.fillColour);
    }
    return true;
  }

  static double _meshDecode(int sample, int maximum, double low, double high) =>
      maximum == 0 ? low : low + sample * (high - low) / maximum;

  /// Splits a type 4 or type 5 triangle whose vertices carry a parameter
  /// into flat facets and adds them to [mesh].
  ///
  /// Clause 8.7.4.5.5 makes the value interpolated across the triangle the
  /// parameter, not the colour: the colour of a point is the function of the
  /// interpolated t. Running the function once per facet is how that curve is
  /// followed, and the subdivision is what keeps the step small. The facets
  /// still go into one mesh, so the rasterizer draws them in a single pass
  /// and the page does not show through their shared edges.
  void _tessellateParametricTriangle(
      _MeshVertex a,
      _MeshVertex b,
      _MeshVertex c,
      double alpha,
      PdfFunction function,
      PdfColorSpace colorSpace,
      _MeshAccumulator mesh) {
    final longest =
        math.max(a.distanceTo(b), math.max(b.distanceTo(c), c.distanceTo(a)));
    final divisions = (longest / 4).ceil().clamp(1, 16);
    for (var i = 0; i < divisions; i++) {
      for (var j = 0; j < divisions - i; j++) {
        final p00 = _MeshVertex.interpolate(a, b, c, i, j, divisions);
        final p10 = _MeshVertex.interpolate(a, b, c, i + 1, j, divisions);
        final p01 = _MeshVertex.interpolate(a, b, c, i, j + 1, divisions);
        mesh.addFlatTriangle(p00, p10, p01,
            _facetColour(p00, p10, p01, alpha, function, colorSpace));
        if (j + i + 1 < divisions) {
          final p11 = _MeshVertex.interpolate(a, b, c, i + 1, j + 1, divisions);
          mesh.addFlatTriangle(p10, p11, p01,
              _facetColour(p10, p11, p01, alpha, function, colorSpace));
        }
      }
    }
  }

  /// The colour of one parametric facet: the function of the mean parameter
  /// of its three corners.
  static int _facetColour(_MeshVertex a, _MeshVertex b, _MeshVertex c,
      double alpha, PdfFunction function, PdfColorSpace colorSpace) {
    final inputs = a.functionInputs;
    if (inputs == null ||
        b.functionInputs == null ||
        c.functionInputs == null) {
      return _withAlpha(
          _rgb((a.r + b.r + c.r) / 3, (a.g + b.g + c.g) / 3,
              (a.b + b.b + c.b) / 3),
          alpha);
    }
    final mean = <double>[
      for (var i = 0; i < inputs.length; i++)
        (inputs[i] + b.functionInputs![i] + c.functionInputs![i]) / 3,
    ];
    final rgb = colorSpace.toRgb(function.evaluate(mean));
    return _withAlpha(_rgb(rgb[0], rgb[1], rgb[2]), alpha);
  }

  // --- graphics state dictionary --------------------------------------------

  /// Applies a `/ExtGState`, Table 58.
  ///
  /// Several entries of Table 58 are deliberately not applied, and not
  /// reported as unsupported either, because they describe an output device
  /// this renderer is not:
  ///
  /// * `/HT` and `/HTP`, the halftone (clause 10.5). Halftoning exists to
  ///   reproduce a continuous tone on a device that cannot hold one — a
  ///   bilevel imagesetter or a printer with a few ink levels — by trading
  ///   spatial resolution for tonal resolution. This renderer's output is
  ///   8 bits per channel with an alpha channel, which *is* a continuous-tone
  ///   device, so there is no tone to approximate. Running the screen anyway
  ///   would turn every smooth fill and every antialiased edge into a dot
  ///   pattern, at a screen frequency chosen for paper, and the result would
  ///   match neither the PDF nor what any viewer shows. The halftone is read
  ///   and preserved by the object model (`PdfExtGState.getHalftone`), which
  ///   is what a prepress consumer actually needs from it.
  /// * `/TR` and `/TR2`, the transfer function (clause 10.4), for the same
  ///   reason: it is a per-device tone correction applied after colour
  ///   conversion, viewers ignore it for screen display, and PDF/A forbids it
  ///   outright. The unrelated `/TR` *inside* a soft-mask dictionary is a part
  ///   of the transparency model rather than a device control, and that one
  ///   is applied — see [_applySoftMask].
  /// * `/BG`, `/BG2`, `/UCR` and `/UCR2`: black generation and undercolour
  ///   removal only have a meaning on the way to CMYK ink.
  /// * `/FL` and `/SM`, the flatness and smoothness tolerances: both name a
  ///   maximum error for approximating curves, and the rasterizer flattens in
  ///   device space at its own tolerance already.
  /// * `/SA`, automatic stroke adjustment (clause 10.6.5), which nudges
  ///   stroke edges onto the pixel grid so that thin lines come out a uniform
  ///   width on a device with hard pixels. An antialiased rasterizer conveys
  ///   a sub-pixel stroke by its coverage instead, which keeps the geometry
  ///   the producer asked for; snapping it would move edges by up to half a
  ///   pixel to fix a problem this renderer does not have.
  /// * `/OP`, `/op` and `/OPM`, overprint: a property of ink on paper.
  ///
  /// None of these is counted in [PdfRenderReport.unsupportedOperators]:
  /// the report is there to say when a page came out incomplete, and a page
  /// that merely names a halftone did not.
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

    // Table 58 lets the graphics state dictionary carry the stroke parameters
    // the `J`, `j`, `M` and `d` operators set. A producer that only ever sets
    // them here would otherwise stroke every line with the defaults.
    final lineCap = await gs.integerEntry(PdfName('LC'));
    if (lineCap != null) {
      state.lineCap = switch (lineCap) {
        1 => BLStrokeCap.round,
        2 => BLStrokeCap.square,
        _ => BLStrokeCap.butt,
      };
    }
    final lineJoin = await gs.integerEntry(PdfName('LJ'));
    if (lineJoin != null) {
      state.lineJoin = switch (lineJoin) {
        1 => BLStrokeJoin.round,
        2 => BLStrokeJoin.bevel,
        _ => BLStrokeJoin.miterBevel,
      };
    }
    final miterLimit = await gs.decimalEntry(PdfName('ML'));
    if (miterLimit != null && miterLimit > 0) state.miterLimit = miterLimit;

    // `/D` is `[[dash array] phase]`, the two operands of `d` in one array.
    final dash = await gs.arrayEntry(PdfName('D'));
    if (dash != null && dash.size() == 2) {
      final array = await dash.get(0);
      if (array is PdfArray) {
        final pattern = <double>[];
        for (var i = 0; i < array.size(); i++) {
          final value = await array.get(i);
          if (value is PdfNumber && value.doubleValue() >= 0) {
            pattern.add(value.doubleValue());
          }
        }
        state.dashArray = pattern;
        final phase = await dash.get(1);
        state.dashPhase = phase is PdfNumber ? phase.doubleValue() : 0;
      }
    }

    // Clause 9.3.8. `/TK` false makes each glyph its own element again.
    final textKnockout = await gs.flagEntry(PdfName('TK'));
    if (textKnockout != null) state.textKnockout = textKnockout;

    if (gs.containsKey(PdfName('SMask'))) {
      final maskObject = await gs.get(PdfName('SMask'), true);
      if (maskObject is PdfDictionary) {
        await _applySoftMask(maskObject, resources, depth);
      } else if (maskObject is PdfName) {
        if (maskObject.getValue() == 'None') {
          context.setOpacityMask(null);
        } else {
          _note('gs:SMask');
        }
      }
    }
    if (gs.containsKey(PdfName('BM'))) {
      await _setBlendMode(await gs.get(PdfName('BM'), true));
    }
  }

  /// Clause 11.6.3: `/BM` is a blend mode name, or an array of names from
  /// which the first one this renderer implements shall be used.
  Future<void> _setBlendMode(PdfObject? value) async {
    if (value is PdfName) {
      final mode = _BlendMode.byName(value.getValue());
      if (mode == null) {
        _note('gs:BM/${value.getValue()}');
        return;
      }
      state.blendMode = mode;
      return;
    }
    if (value is PdfArray) {
      for (var i = 0; i < value.size(); i++) {
        final entry = await value.get(i);
        if (entry is! PdfName) continue;
        final mode = _BlendMode.byName(entry.getValue());
        if (mode != null) {
          state.blendMode = mode;
          return;
        }
      }
      // An array with nothing recognisable in it means Normal, which is what
      // the array form is for: naming a preferred mode with a fallback.
      state.blendMode = _BlendMode.normal;
      return;
    }
    _note('gs:BM');
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
    var backdrop = 0x00000000;
    if (subtype == 'Luminosity') {
      final backdropArray = await mask.arrayEntry(PdfName('BC'));
      if (backdropArray != null) {
        final groupDictionary = await group.dictionaryEntry(PdfName('Group'));
        final colourObject = await groupDictionary?.get(PdfName('CS'), true);
        final colourSpace = colourObject == null
            ? null
            : await PdfColorSpace.makeColorSpace(colourObject);
        final components = await backdropArray.toDoubleArray();
        if (colourSpace == null ||
            components.length != colourSpace.getNumberOfComponents()) {
          _note('gs:SMask-backdrop');
        } else {
          try {
            final rgb = colourSpace.toRgb(components);
            backdrop = _rgb(rgb[0], rgb[1], rgb[2]);
          } on Object {
            _note('gs:SMask-backdrop');
          }
        }
      }
    }
    final surface = BLImage(context.image.width, context.image.height)
      ..clear(backdrop);
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

    PdfFunction? transfer;
    final transferObject = await mask.get(PdfName('TR'), true);
    if (transferObject != null &&
        !(transferObject is PdfName &&
            (transferObject.getValue() == 'Identity' ||
                transferObject.getValue() == 'Default'))) {
      transfer = await PdfFunction.parse(transferObject);
      if (transfer == null ||
          transfer.inputCount != 1 ||
          transfer.outputCount != 1) {
        _note('gs:SMask-transfer');
        transfer = null;
      }
    }
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
      if (transfer != null) {
        try {
          coverage[i] =
              (transfer.evaluate([coverage[i] / 255]).first.clamp(0.0, 1.0) *
                      255)
                  .round();
        } on Object {
          _note('gs:SMask-transfer');
          transfer = null;
        }
      }
    }
    context.setOpacityMask(coverage);
    for (final entry in nested.unsupported.entries) {
      unsupported[entry.key] = (unsupported[entry.key] ?? 0) + entry.value;
    }
    glyphsSkipped += nested.glyphsSkipped;
    imagesSkipped += nested.imagesSkipped;
    fontFailures.addAll(nested.fontFailures);
    fontsSubstituted.addAll(nested.fontsSubstituted);
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
    final substituted = resolved?.substitutedFont;
    if (substituted != null) fontsSubstituted.add(substituted);
  }

  /// Draws `Tj`, `TJ`, `'` and `"`.
  Future<void> _showText(
    PdfContentOperation op,
    PdfDictionary? resources,
    int depth,
  ) async {
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
      await _showString(operand.getValueBytes(), resources, depth);
      return;
    }

    if (operand is PdfArray) {
      // In `TJ` a number displaces the next glyph by -n/1000 text units,
      // which is how justified text and kerning corrections are encoded.
      for (var i = 0; i < operand.size(); i++) {
        final item = await operand.get(i);
        if (item is PdfString) {
          await _showString(item.getValueBytes(), resources, depth);
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

  Future<void> _showString(
    Uint8List? bytes,
    PdfDictionary? resources,
    int depth,
  ) async {
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

    // Clause 9.3.6, Table 106. Mode 3 draws nothing at all, which is what
    // keeps the text layer of a scanned page hidden; modes 4 to 7 additionally
    // add the glyph outlines to the clipping path, and mode 7 only does that.
    final mode = state.renderMode;
    final fill = mode == 0 || mode == 2 || mode == 4 || mode == 6;
    final stroke = mode == 1 || mode == 2 || mode == 5 || mode == 6;
    final clip = mode >= 4 && mode <= 7;
    if (clip) {
      // An empty union clips everything away, which is the right answer for a
      // text object that shows no glyphs under a clipping mode.
      _textClipVertices ??= <double>[];
      _textClipContours ??= <int>[];
    }

    // Clause 9.3.8: a Type 3 glyph is a content stream rather than a single
    // outline, so the text-object knockout would apply to the shapes inside
    // one glyph as well. That is not what the clause describes, and applying
    // it would change glyphs that are correct today, so it is left alone.
    if ((fill || stroke) && font.type3 == null) _beginTextKnockout();

    for (final code in font.codes(bytes)) {
      if (fill || stroke || clip) {
        await _drawGlyph(font, code,
            fill: fill,
            stroke: stroke,
            clip: clip,
            resources: resources,
            depth: depth);
      }
      _advanceForCode(code, font.width(code), composite: font.composite);
    }
  }

  /// Intersects the clip with the glyph outlines collected since `BT`.
  Future<void> _applyTextClip() async {
    final vertices = _textClipVertices;
    final contours = _textClipContours;
    _textClipVertices = null;
    _textClipContours = null;

    final width = context.image.width;
    final height = context.image.height;

    if (vertices == null || contours == null) {
      // Clause 9.4.3: at ET the glyph outlines accumulated since BT become the
      // clipping path. A text object that never reached a show-text operator
      // accumulated nothing, so under a clipping mode the union is empty and
      // the clip removes the whole page. Only a text object that used no
      // clipping mode at all leaves the existing clip untouched.
      final mode = state.renderMode;
      if (mode < 4 || mode > 7) return;
      context.intersectClipMask(Uint8List(width * height));
      return;
    }
    final coverage = Uint8List(width * height);
    if (vertices.length >= 6) {
      // The outlines are rasterized once, as a single non-zero path: glyph
      // contours are wound consistently, so non-zero is their union and
      // overlapping glyphs do not punch holes in each other.
      final surface = BLImage(width, height);
      final scratch = BLContext(surface);
      await scratch.fillPolygon(
        vertices,
        contourVertexCounts: contours,
        color: 0xFFFFFFFF,
        rule: BLFillRule.nonZero,
      );
      scratch.flush();
      for (var i = 0; i < coverage.length; i++) {
        coverage[i] = (surface.pixels[i] >>> 24) & 0xff;
      }
    }
    context.intersectClipMask(coverage);
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
    required bool fill,
    required bool stroke,
    required bool clip,
    required PdfDictionary? resources,
    required int depth,
  }) async {
    final type3 = font.type3;
    if (type3 != null) {
      // Clause 9.6.5: a Type 3 glyph is a content stream, not an outline.
      // The text rendering mode cannot select fill or stroke for it — the
      // procedure paints itself — so only the clipping modes are reported.
      if (clip) _note('Tr:type3-clip');
      if (!fill && !stroke) return;
      await _drawType3Glyph(type3, code, resources: resources, depth: depth);
      return;
    }
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
    // `glyphOutlineUnits` is prepared for a screen rasterizer: ascenders have
    // negative Y. Convert that back to PDF's y-up glyph space here. The page
    // device matrix performs a separate, later flip from PDF to image space.
    final scale = state.fontSize / face.unitsPerEm;
    final parameters = BLMatrix2D(
      scale * state.horizontalScale,
      0,
      0,
      -scale,
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

    if (clip) {
      _textClipVertices!.addAll(mapped);
      // Contour counts are in points, and one glyph's contours have to stay
      // separated from the next glyph's, so a missing list becomes a single
      // contour covering this glyph rather than nothing.
      final counts = outline.contourVertexCounts;
      if (counts == null || counts.isEmpty) {
        _textClipContours!.add(mapped.length ~/ 2);
      } else {
        _textClipContours!.addAll(counts);
      }
    }
    if (!fill && !stroke) return;

    var left = mapped[0], right = mapped[0];
    var top = mapped[1], bottom = mapped[1];
    for (var i = 2; i < mapped.length; i += 2) {
      left = math.min(left, mapped[i]);
      right = math.max(right, mapped[i]);
      top = math.min(top, mapped[i + 1]);
      bottom = math.max(bottom, mapped[i + 1]);
    }
    final strokeReach = stroke
        ? (state.lineWidth * _averageScale(state.ctm) * state.miterLimit)
            .ceil()
            .clamp(1, 1 << 20)
        : 0;
    final bounds = _boundsOf([(left, top), (right, bottom)]);

    // Table 106 names modes 2 and 6 "Fill, then stroke": the stroke has to
    // land on top of the fill, so the fill goes down first.
    if (fill) {
      // Glyph outlines are always non-zero: counters are wound the other way
      // round, and even-odd would punch holes through overlapping contours.
      await _paint(
        () => context.fillPolygon(
          mapped,
          contourVertexCounts: outline.contourVertexCounts,
          color: _withAlpha(state.fillColour, state.fillAlpha),
          rule: BLFillRule.nonZero,
        ),
        bounds: bounds,
        constantAlpha: state.fillAlpha,
      );
    }
    if (stroke) {
      final scale = _averageScale(state.ctm);
      await _paint(
        () => context.strokePolygon(
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
        ),
        bounds: BLRectI(bounds.x - strokeReach, bounds.y - strokeReach,
            bounds.width + strokeReach * 2, bounds.height + strokeReach * 2),
        constantAlpha: state.strokeAlpha,
      );
    }
  }

  /// Runs one Type 3 glyph procedure, ISO 32000-1 clause 9.6.5.
  ///
  /// The procedure is a content stream drawn in the font's glyph space, so it
  /// is executed exactly like a form XObject whose matrix is
  /// `FontMatrix x [Tfs*Th 0 0 Tfs 0 Trise] x Tm x CTM`. Everything else the
  /// glyph inherits from the graphics state in force at the show-text
  /// operator, which is what lets a `d1` glyph take the current fill colour.
  ///
  /// The advance still comes from `/Widths`, never from the `wx` operand of
  /// `d0`/`d1`: Table 112 requires the two to agree, and `/Widths` is what the
  /// producer laid the line out against.
  Future<void> _drawType3Glyph(
    PdfType3Font font,
    int code, {
    required PdfDictionary? resources,
    required int depth,
  }) async {
    if (depth >= _maxDepth) return;

    final PdfStream? procedure;
    try {
      procedure = await font.procedure(code);
    } on Object {
      glyphsSkipped++;
      return;
    }
    if (procedure == null) {
      // The encoding names no procedure for this code, or `/CharProcs` has
      // no such key. Nothing can be drawn, and the report should say so.
      glyphsSkipped++;
      return;
    }
    final content = await procedure.getBytes();
    // A blank glyph, a space for instance, has an empty procedure.
    if (content == null || content.isEmpty) return;

    final m = font.fontMatrix;
    final parameters = BLMatrix2D(
      state.fontSize * state.horizontalScale,
      0,
      0,
      state.fontSize,
      0,
      state.rise,
    );
    final glyphToDevice = BLMatrix2D(m[0], m[1], m[2], m[3], m[4], m[5])
        .multiply(parameters)
        .multiply(_textMatrix)
        .multiply(state.ctm);

    final saved = state.clone();
    final savedStack = _stack.length;
    final savedTextMatrix = _textMatrix;
    final savedLineMatrix = _textLineMatrix;
    final savedInType3 = _inType3Glyph;
    final savedShapeOnly = _type3ShapeOnly;
    final savedTextKnockout = _textKnockoutActive;
    // A procedure may open a text object of its own, and `BT` discards the
    // outlines the enclosing text object has collected for its clip.
    final savedClipVertices = _textClipVertices;
    final savedClipContours = _textClipContours;
    context.save();

    state.ctm = glyphToDevice;
    // A glyph description is not itself shown text: resetting the rendering
    // mode keeps a clipping mode on the outer text object from being applied
    // again, recursively, to everything the procedure draws.
    state.renderMode = 0;
    _inType3Glyph = true;
    _type3ShapeOnly = false;
    _textKnockoutActive = false;

    try {
      await run(content, font.resources ?? resources, depth + 1);
    } finally {
      _inType3Glyph = savedInType3;
      _type3ShapeOnly = savedShapeOnly;
      _textKnockoutActive = savedTextKnockout;
      _textMatrix = savedTextMatrix;
      _textLineMatrix = savedLineMatrix;
      _textClipVertices = savedClipVertices;
      _textClipContours = savedClipContours;
      context.restore();
      while (_stack.length > savedStack) {
        _stack.removeLast();
      }
      state = saved;
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

    // Clause 11.6.6: a form that carries a transparency group dictionary is
    // not just executed in place. Its content is composited as a unit, so the
    // graphics state's alpha, soft mask and blend mode apply once to the
    // finished group rather than to each object inside it.
    final group = await xobject.dictionaryEntry(PdfName('Group'));
    final isTransparency =
        (await group?.nameEntry(PdfName.s))?.getValue() == 'Transparency';
    if (group != null && isTransparency) {
      await _drawTransparencyGroup(xobject, group, resources, depth);
      return;
    }

    await _runForm(xobject, resources, depth);
  }

  /// Runs a form XObject with its own matrix and resources, inside a saved
  /// state, clipped to its bounding box (clause 8.10.2).
  Future<void> _runForm(
    PdfStream xobject,
    PdfDictionary? resources,
    int depth,
  ) async {
    final saved = state.clone();
    final savedStack = _stack.length;
    context.save();

    await _applyFormMatrix(xobject);
    await _clipToFormBBox(xobject);

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

  Future<void> _applyFormMatrix(PdfStream xobject) async {
    final matrix = await xobject.arrayEntry(PdfName('Matrix'));
    if (matrix == null || matrix.size() != 6) return;
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

  /// The form's `/BBox`, mapped to device space, or null when it has none.
  Future<List<(double, double)>?> _formBBoxCorners(PdfStream xobject) async {
    final bbox = await xobject.arrayEntry(PdfName('BBox'));
    if (bbox == null || bbox.size() != 4) return null;
    final b = <double>[];
    for (var i = 0; i < 4; i++) {
      final value = await bbox.get(i);
      b.add(value is PdfNumber ? value.doubleValue() : 0);
    }
    final x0 = math.min(b[0], b[2]);
    final y0 = math.min(b[1], b[3]);
    final x1 = math.max(b[0], b[2]);
    final y1 = math.max(b[1], b[3]);
    return <(double, double)>[
      _device(x0, y0),
      _device(x1, y0),
      _device(x1, y1),
      _device(x0, y1),
    ];
  }

  static BLPath _polygon(List<(double, double)> corners) {
    final path = BLPath()..moveTo(corners[0].$1, corners[0].$2);
    for (var i = 1; i < corners.length; i++) {
      path.lineTo(corners[i].$1, corners[i].$2);
    }
    return path..close();
  }

  Future<void> _clipToFormBBox(PdfStream xobject) async {
    final corners = await _formBBoxCorners(xobject);
    if (corners == null) return;
    context.clipToPath(_polygon(corners));
  }

  /// Composites a transparency group XObject, clauses 11.4 and 11.6.6.
  ///
  /// The group's elements are drawn onto their own surface — transparent for
  /// an isolated group, a copy of the backdrop otherwise — with the blend
  /// mode, alpha constants and soft mask reset, exactly as the `Do` operator
  /// is defined to do. The finished surface is composited once afterwards,
  /// with the transparency parameters that were in force at the `Do`.
  Future<void> _drawTransparencyGroup(
    PdfStream xobject,
    PdfDictionary group,
    PdfDictionary? resources,
    int depth,
  ) async {
    if (depth >= _maxDepth) return;
    final isolated = await group.flagEntry(PdfName('I')) ?? false;
    final knockout = await group.flagEntry(PdfName('K')) ?? false;
    final constantAlpha = state.fillAlpha.clamp(0.0, 1.0);
    final mode = state.blendMode;
    final target = context;

    final saved = state.clone();
    final savedStack = _stack.length;
    final savedKnockout = _knockoutBackdrop;
    final savedTextKnockout = _textKnockoutActive;
    final savedBusy = _layerBusy;

    // The bounding box has to be mapped through the form's own matrix, so the
    // matrix goes on first; knowing the box up front keeps the initialisation
    // and the final compositing to the pixels the group can actually reach.
    await _applyFormMatrix(xobject);
    final corners = await _formBBoxCorners(xobject);
    final bounds = _clampToSurface(
        corners == null ? null : _boundsOf(corners), target.image);
    if (bounds == null) {
      state = saved;
      return;
    }

    // Nothing else composites against a group that changes nothing: a
    // non-isolated, non-knockout group painted with Normal, full alpha and no
    // soft mask produces exactly what drawing its content in place would
    // (clause 11.4.4, NOTE 5).
    if (!isolated &&
        !knockout &&
        mode == _BlendMode.normal &&
        constantAlpha >= 1 &&
        target.opacityMask == null &&
        _knockoutBackdrop == null) {
      state = saved;
      await _runForm(xobject, resources, depth);
      return;
    }

    final surface = BLImage(target.image.width, target.image.height);
    if (!isolated) {
      // A non-isolated group starts from everything painted in the parent so
      // far, so blend modes inside the group see the real backdrop.
      _copyRegion(target.image, surface, bounds);
    }

    final groupContext = BLContext(surface);
    groupContext.setClipRect(target.clipRect);
    final clipMask = target.clipMask;
    if (clipMask != null) groupContext.intersectClipMask(clipMask);
    if (corners != null) groupContext.clipToPath(_polygon(corners));

    context = groupContext;
    _layerBusy = false;

    // Clause 11.6.6: the group's own content starts from Normal, alpha 1 and
    // no soft mask, so those are not applied twice.
    state.fillAlpha = 1;
    state.strokeAlpha = 1;
    state.blendMode = _BlendMode.normal;
    _knockoutBackdrop = knockout ? Uint32List.fromList(surface.pixels) : null;
    // The group's own content starts a fresh text-knockout scope: an `ET`
    // inside it must not drop the backdrop the group is knocking out against.
    _textKnockoutActive = false;

    final formResources =
        await xobject.dictionaryEntry(PdfName.resources) ?? resources;
    final content = await xobject.getBytes();
    if (content != null) {
      await run(content, formResources, depth + 1);
    }
    groupContext.flush();

    context = target;
    _knockoutBackdrop = savedKnockout;
    _textKnockoutActive = savedTextKnockout;
    _layerBusy = savedBusy;
    state = saved;
    while (_stack.length > savedStack) {
      _stack.removeLast();
    }

    _composeGroup(target, surface, bounds,
        isolated: isolated, mode: mode, constantAlpha: constantAlpha);
  }

  static void _copyRegion(BLImage from, BLImage to, BLRectI rect) {
    final source = from.pixels;
    final destination = to.pixels;
    final width = from.width;
    for (var y = rect.y; y < rect.y + rect.height; y++) {
      final row = y * width;
      destination.setRange(
          row + rect.x, row + rect.x + rect.width, source, row + rect.x);
    }
  }

  /// Composites a finished group surface onto its backdrop.
  void _composeGroup(
    BLContext target,
    BLImage surface,
    BLRectI rect, {
    required bool isolated,
    required _BlendMode mode,
    required double constantAlpha,
  }) {
    final destination = target.image.pixels;
    final group = surface.pixels;
    final opacity = target.opacityMask;
    final knockout = _knockoutBackdrop;
    final width = target.image.width;
    final backdrop = List<double>.filled(3, 0);
    final colour = List<double>.filled(3, 0);
    final blended = List<double>.filled(3, 0);

    for (var y = rect.y; y < rect.y + rect.height; y++) {
      final row = y * width;
      for (var x = rect.x; x < rect.x + rect.width; x++) {
        final index = row + x;
        final source = group[index];
        if (((source >>> 24) & 0xff) == 0) continue;

        var factor = constantAlpha;
        if (opacity != null) factor *= opacity[index] / 255;
        if (factor <= 0) continue;

        final base = knockout ?? destination;
        final backdropPixel = base[index];
        var pixel = source;
        if (!isolated) {
          // Clause 11.4.4: the backdrop's contribution is removed before the
          // group is composited, or it would be counted twice.
          final removed = _removeBackdrop(backdropPixel, source);
          if (removed == null) {
            // With an opaque backdrop the group's own alpha cannot be
            // recovered. Averaging the group result back over the backdrop is
            // exactly right for Normal, which this case almost always is, and
            // the closest available answer otherwise.
            if (mode != _BlendMode.normal) _note('Do:group-opaque-backdrop');
            destination[index] = _mix(
                destination[index],
                knockout == null ? source : _mix(backdropPixel, source, 1),
                factor);
            continue;
          }
          pixel = removed;
        }
        final shape = ((pixel >>> 24) & 0xff) / 255;
        if (shape <= 0) continue;

        final composed = _composite(
            backdropPixel,
            pixel,
            knockout == null ? shape * factor : factor,
            mode,
            backdrop,
            colour,
            blended);
        destination[index] = knockout == null
            ? composed
            : _mix(destination[index], composed, shape);
      }
    }
  }

  /// Undoes compositing with [backdropPixel], recovering the group's own
  /// colour and alpha, or null when the backdrop is opaque and the group's
  /// alpha is therefore not recoverable.
  static int? _removeBackdrop(int backdropPixel, int groupPixel) {
    final a0 = ((backdropPixel >>> 24) & 0xff) / 255;
    final an = ((groupPixel >>> 24) & 0xff) / 255;
    if (a0 <= 0) return groupPixel;
    if (a0 >= 1) return null;
    final ag = ((an - a0) / (1 - a0)).clamp(0.0, 1.0);
    if (ag <= 0) return 0;
    final scale = a0 / ag - a0;
    var result = (ag * 255).round().clamp(0, 255) << 24;
    for (var shift = 16; shift >= 0; shift -= 8) {
      final cn = ((groupPixel >>> shift) & 0xff) / 255;
      final c0 = ((backdropPixel >>> shift) & 0xff) / 255;
      final value = cn + (cn - c0) * scale;
      result |= (value.clamp(0.0, 1.0) * 255).round() << shift;
    }
    return result;
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

    final bounds = _boundsOf(corners);
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
      await _paint(
        () => _fillWithPattern(path, surface, inverse, interpolate),
        bounds: bounds,
        constantAlpha: state.fillAlpha,
      );
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
    await _paint(
      () => _fillWithPattern(path, surface, inverse, interpolate),
      bounds: bounds,
      constantAlpha: state.fillAlpha,
    );
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
