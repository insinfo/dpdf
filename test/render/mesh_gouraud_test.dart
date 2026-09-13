import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// A one-page document whose content stream is [content].
Future<PdfDocument> _document(String content, PdfDictionary resources) async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  page.pdfRepresentation()
    ..put(PdfName.mediaBox, PdfArray.fromDoubles(const [0, 0, 100, 100]))
    ..put(PdfName.contents,
        PdfStream.withBytes(Uint8List.fromList(latin1.encode(content)), 0))
    ..put(PdfName.resources, resources);
  await document.close();
  return PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
}

Future<PdfRenderedPage> _render(String content, PdfDictionary resources) async {
  final document = await _document(content, resources);
  try {
    return await PdfPageRenderer.render((await document.pageAt(1))!,
        options: const PdfRenderOptions(dpi: 72));
  } finally {
    await document.close();
  }
}

({int a, int r, int g, int b}) _at(PdfRenderedPage page, int x, int y) {
  final word = page.pixels[y * page.width + x];
  return (
    a: (word >> 24) & 0xff,
    r: (word >> 16) & 0xff,
    g: (word >> 8) & 0xff,
    b: word & 0xff,
  );
}

/// Rec. 601 luma, which is what a seam shows up in.
double _luma(({int a, int r, int g, int b}) pixel) =>
    0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;

/// A shading stream with the byte widths every mesh test here uses.
PdfStream _mesh(List<int> bytes, int type, PdfObject colourSpace,
    List<double> decode, Map<String, PdfObject> extra) {
  final stream = PdfStream.withBytes(Uint8List.fromList(bytes), 0)
    ..put(PdfName.shadingType, PdfNumber.fromInt(type))
    ..put(PdfName.colorSpace, colourSpace)
    ..put(PdfName('BitsPerCoordinate'), PdfNumber.fromInt(8))
    ..put(PdfName('BitsPerComponent'), PdfNumber.fromInt(8))
    ..put(PdfName('Decode'), PdfArray.fromDoubles(decode));
  extra.forEach((key, value) => stream.put(PdfName(key), value));
  return stream;
}

PdfDictionary _shadingResource(PdfStream shading) => PdfDictionary()
  ..put(PdfName.shading, PdfDictionary()..put(PdfName('S'), shading));

/// A user-space coordinate in 0..100 as the 8-bit sample `Decode` undoes.
int _coord(double value) => (value * 255 / 100).round();

const _rgbDecode = <double>[0, 100, 0, 100, 0, 1, 0, 1, 0, 1];

/// The twelve boundary control points of the unit square, in the order
/// ISO 32000-1 table 85 lists them for a type 6 patch, scaled to 0..100.
const _squareBoundary = <int>[
  0, 0, //
  0, 85,
  0, 170,
  0, 255,
  85, 255,
  170, 255,
  255, 255,
  255, 170,
  255, 85,
  255, 0,
  170, 0,
  85, 0,
];

void main() {
  group('Gouraud interpolation of mesh shadings', () {
    test('a type 4 facet varies in colour between its three vertices',
        () async {
      // One triangle: red at the bottom left, green at the bottom right and
      // blue at the top. Averaging the three corners, which is what a
      // per-facet flat fill does, would paint the whole triangle the same
      // dull grey.
      final shading = _mesh(<int>[
        0, _coord(10), _coord(10), 255, 0, 0, //
        0, _coord(90), _coord(10), 0, 255, 0,
        0, _coord(50), _coord(90), 0, 0, 255,
      ], 4, PdfName.deviceRgb, _rgbDecode, {
        'BitsPerFlag': PdfNumber.fromInt(8),
      });

      final page = await _render('/S sh', _shadingResource(shading));

      // Device y grows downward, so user (10, 10) is near the bottom left.
      final nearRed = _at(page, 18, 82);
      final nearGreen = _at(page, 82, 82);
      final nearBlue = _at(page, 50, 20);
      final centre = _at(page, 50, 62);

      expect(nearRed.r, greaterThan(160));
      expect(nearRed.g, lessThan(90));
      expect(nearRed.b, lessThan(90));

      expect(nearGreen.g, greaterThan(160));
      expect(nearGreen.r, lessThan(90));
      expect(nearGreen.b, lessThan(90));

      expect(nearBlue.b, greaterThan(160));
      expect(nearBlue.r, lessThan(90));
      expect(nearBlue.g, lessThan(90));

      // The centre is the average of the three, and every corner sample is
      // far from it: the facet is a gradient, not a flat fill.
      for (final component in <int>[centre.r, centre.g, centre.b]) {
        expect(component, closeTo(85, 30));
      }
      expect(page.report.unsupportedOperators, isEmpty);
    });

    test('a flat type 6 patch leaves no seam between its facets', () async {
      // Every corner carries the same mid grey, so the whole patch must come
      // out one colour. A patch this size is tessellated into 24 x 24 cells,
      // and compositing 1152 antialiased triangles one at a time used to
      // leave the white page showing through every shared edge.
      final shading = _mesh(<int>[
        0,
        ..._squareBoundary,
        128, 128, 128, //
        128, 128, 128,
        128, 128, 128,
        128, 128, 128,
      ], 6, PdfName.deviceRgb, _rgbDecode, {
        'BitsPerFlag': PdfNumber.fromInt(8),
      });

      final page = await _render('/S sh', _shadingResource(shading));

      expect(_at(page, 50, 50).r, closeTo(128, 2));
      var brightest = 0.0;
      var brightestAt = '';
      for (var y = 4; y < 96; y++) {
        for (var x = 4; x < 96; x++) {
          final luma = _luma(_at(page, x, y));
          if (luma > brightest) {
            brightest = luma;
            brightestAt = '($x, $y)';
          }
        }
      }
      // The fill is 128; anything appreciably lighter is page white leaking
      // through a seam.
      expect(brightest, lessThan(132),
          reason: 'seam at $brightestAt inside a flat patch');
      expect(page.report.unsupportedOperators, isEmpty);
    });

    test('a type 5 lattice has no bright line on its shared edges', () async {
      // Two columns of quads, so the mesh has an interior vertical edge at
      // x = 50 as well as the diagonal of each quad.
      final shading = _mesh(<int>[
        _coord(10), _coord(10), 26, 26, 26, //
        _coord(50), _coord(10), 128, 128, 128,
        _coord(90), _coord(10), 230, 230, 230,
        _coord(10), _coord(90), 26, 26, 26,
        _coord(50), _coord(90), 128, 128, 128,
        _coord(90), _coord(90), 230, 230, 230,
      ], 5, PdfName.deviceRgb, _rgbDecode, {
        'VerticesPerRow': PdfNumber.fromInt(3),
      });

      final page = await _render('/S sh', _shadingResource(shading));

      // Scan the line that crosses the shared edge: no pixel on it may be
      // lighter than both of its neighbours, which is what a seam looks like.
      final row = <double>[
        for (var x = 14; x <= 86; x++) _luma(_at(page, x, 50))
      ];
      for (var i = 1; i < row.length - 1; i++) {
        expect(row[i] > row[i - 1] + 1 && row[i] > row[i + 1] + 1, isFalse,
            reason: 'bright pixel at x = ${14 + i} on the scan line: '
                '${row[i - 1]}, ${row[i]}, ${row[i + 1]}');
      }
      expect(row.first, lessThan(60));
      expect(row.last, greaterThan(200));
      expect(page.report.unsupportedOperators, isEmpty);
    });

    test(
        'the parameter of a type 5 mesh is still interpolated before the '
        'function runs', () async {
      // t runs 0 to 1 across the page and the function squares it, so the
      // grey a quarter of the way across must be 0.0625, not 0.25.
      final function = PdfDictionary()
        ..put(PdfName('FunctionType'), PdfNumber.fromInt(2))
        ..put(PdfName('Domain'), PdfArray.fromDoubles(const [0, 1]))
        ..put(PdfName('C0'), PdfArray.fromDoubles(const [0]))
        ..put(PdfName('C1'), PdfArray.fromDoubles(const [1]))
        ..put(PdfName('N'), PdfNumber(2));
      final shading = _mesh(<int>[
        0, 0, 0, //
        255, 0, 255,
        0, 255, 0,
        255, 255, 255,
      ], 5, PdfName.deviceGray, const [0, 100, 0, 100, 0, 1], {
        'VerticesPerRow': PdfNumber.fromInt(2),
        'Function': function,
      });

      final page = await _render('/S sh', _shadingResource(shading));

      for (final sample in const <List<double>>[
        [25, 16.6],
        [50, 65.0],
        [75, 145.0],
      ]) {
        final grey = _at(page, sample[0].toInt(), 50).r;
        // Interpolating the colour instead of t would give 65, 129 and 193.
        expect(grey, closeTo(sample[1], 30),
            reason: 't must be squared at x = ${sample[0]}, '
                'not interpolated in RGB');
      }

      // The facets are flat, as the non-affine function requires, but they
      // are one mesh, so the ramp still has no bright pixel on a facet edge.
      final row = <double>[
        for (var x = 2; x < 98; x++) _luma(_at(page, x, 50))
      ];
      for (var i = 1; i < row.length - 1; i++) {
        expect(row[i] > row[i - 1] + 1 && row[i] > row[i + 1] + 1, isFalse,
            reason: 'seam at x = ${2 + i}: '
                '${row[i - 1]}, ${row[i]}, ${row[i + 1]}');
      }
      expect(page.report.unsupportedOperators, isEmpty);
    });
  });
}
