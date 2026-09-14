import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// A shading is a function; a gradient is a table. Drawing one as the other
/// means resampling, and what resampling destroys first is the discontinuity:
/// a type 4 function whose `ifelse` switches colour abruptly falls between two
/// samples, the gap between them is interpolated, and the page gets a ramp
/// where the document asked for an edge.
///
/// That was measurable. With the renderer sampling the function at 257 points,
/// a hard step reached an A4 page at 300 dpi as a ramp 10 px wide. The number
/// of samples is not free to choose: it has to line up with the table the
/// rasterizer builds, so the fix is 1024 -- the table's maximum -- rather than
/// "more".
///
/// `dgfx`'s own `test/gradient_lut_resolution_test.dart` holds the other half,
/// the table sizing. This one holds the sampling, and asserts on the rendered
/// page so it keeps meaning something if the two are ever decoupled.
Future<PdfRenderedPage> _render(
    String content, PdfDictionary resources, double size, double dpi) async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  page.pdfRepresentation()
    ..put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, size, size]))
    ..put(PdfName.contents,
        PdfStream.withBytes(Uint8List.fromList(latin1.encode(content)), 0))
    ..put(PdfName.resources, resources);
  await document.close();
  final doc = await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
  try {
    return await PdfPageRenderer.render((await doc.pageAt(1))!,
        options: PdfRenderOptions(dpi: dpi));
  } finally {
    await doc.close();
  }
}

PdfStream _type4(String program, List<double> domain, List<double> range) =>
    PdfStream.withBytes(Uint8List.fromList(latin1.encode(program)), 0)
      ..put(PdfName('FunctionType'), PdfNumber.fromInt(4))
      ..put(PdfName('Domain'), PdfArray.fromDoubles(domain))
      ..put(PdfName('Range'), PdfArray.fromDoubles(range));

/// An axial shading across the page whose colour steps from blue to red at
/// `at`, expressed as a PostScript calculator function.
Future<PdfRenderedPage> _axialStep(double at, double size, double dpi) {
  final function = _type4('{ $at lt { 0 0 1 } { 1 0 0 } ifelse }', const [0, 1],
      const [0, 1, 0, 1, 0, 1]);
  final shading = PdfDictionary()
    ..put(PdfName.shadingType, PdfNumber.fromInt(2))
    ..put(PdfName.colorSpace, PdfName('DeviceRGB'))
    ..put(PdfName.coords, PdfArray.fromDoubles([0, 0, size, 0]))
    ..put(PdfName.function, function);
  return _render(
      'q 0 0 $size $size re W n /S sh Q',
      PdfDictionary()
        ..put(PdfName.shading, PdfDictionary()..put(PdfName('S'), shading)),
      size,
      dpi);
}

bool _isBlue(int c) => ((c >> 16) & 0xFF) == 0 && (c & 0xFF) == 0xFF;
bool _isRed(int c) => ((c >> 16) & 0xFF) == 0xFF && (c & 0xFF) == 0;

void main() {
  group('a discontinuous shading function keeps its edge', () {
    // 595 pt is A4's width; 300 dpi is where the ramp was widest.
    const size = 595.0;

    for (final dpi in [72.0, 150.0, 300.0]) {
      test('axial step survives at $dpi dpi', () async {
        // The step position is swept, because where it falls relative to the
        // sample grid is exactly what decides whether it survives. One
        // position only ever proves the lucky case.
        var widestRamp = 0;
        var worstOffset = 0.0;
        var worstAt = 0.0;
        for (var k = 1; k < 12; k++) {
          final at = 0.2 + 0.6 * k / 12;
          final page = await _axialStep(at, size, dpi);
          final row = page.height ~/ 2;
          var flip = -1, ramp = 0;
          // The outermost column is the antialiased edge of the fill itself,
          // which is not what is under test.
          for (var x = 1; x < page.width - 1; x++) {
            final pixel = page.pixels[row * page.width + x];
            if (flip < 0 && _isRed(pixel)) flip = x;
            if (!_isBlue(pixel) && !_isRed(pixel)) ramp++;
          }
          expect(flip, greaterThan(0), reason: 'the shading never turned red');
          if (ramp > widestRamp) widestRamp = ramp;
          final offset = (flip - at * page.width).abs();
          if (offset > worstOffset) {
            worstOffset = offset;
            worstAt = at;
          }
        }

        expect(widestRamp, lessThanOrEqualTo(2),
            reason: 'the step was resampled into a ramp $widestRamp px wide; '
                'at 257 samples this was 10 px at 300 dpi');
        expect(worstOffset, lessThan(2.0),
            reason: 'the edge landed ${worstOffset.toStringAsFixed(2)} px from '
                'where the function puts it (step at $worstAt)');
      });
    }

    test('a genuine ramp is still drawn as a ramp', () async {
      // Guard case. Sharpening the sampling must not turn every gradient into
      // a staircase: an exponential function has no discontinuity, and the
      // page must show the smooth sweep, not two flat colours.
      final function = _type4(
          '{ dup dup }', const [0, 1], const [0, 1, 0, 1, 0, 1]);
      final shading = PdfDictionary()
        ..put(PdfName.shadingType, PdfNumber.fromInt(2))
        ..put(PdfName.colorSpace, PdfName('DeviceRGB'))
        ..put(PdfName.coords, PdfArray.fromDoubles([0, 0, 595, 0]))
        ..put(PdfName.function, function);
      final page = await _render(
          'q 0 0 595 595 re W n /S sh Q',
          PdfDictionary()
            ..put(PdfName.shading, PdfDictionary()..put(PdfName('S'), shading)),
          595,
          150);

      final row = page.height ~/ 2;
      final levels = <int>{};
      for (var x = 1; x < page.width - 1; x++) {
        levels.add((page.pixels[row * page.width + x] >> 16) & 0xFF);
      }
      // A full 0..255 sweep across the page: anything much less means the
      // gradient was quantised into bands.
      expect(levels.length, greaterThan(200),
          reason: 'the ramp came out in ${levels.length} distinct levels');
    });
  });
}
