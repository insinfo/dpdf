import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// The page is 120 points square and the area is the 40-point square in the
/// middle of it, so a shape can be made to reach into the area from any side,
/// to surround it, or to sit inside it.
const _pageSize = 120.0;
const _area = PdfRedactionArea(1, left: 40, bottom: 40, right: 80, top: 80);

/// Eight pixels to the point, which puts every edge of [_area] exactly on a
/// pixel boundary. Nothing here then depends on how a partly covered pixel is
/// resolved at the edge of the area itself.
const _dpi = 72.0 * 8;
const _scale = 8.0;

Future<Uint8List> _page(String content) async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  page.pdfRepresentation()
    ..put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, _pageSize, _pageSize]))
    ..put(PdfName.contents,
        PdfStream.withBytes(Uint8List.fromList(latin1.encode(content)), 0));
  await document.close();
  return output.takeBytes();
}

Future<Uint8List> _redact(Uint8List source,
        {List<PdfRedactionArea> areas = const [_area]}) =>
    PdfAreaRedaction.apply(source, areas,
        options: const PdfAreaRedactionOptions(paintOverlay: false));

/// The page's content stream, decompressed, which is where a coordinate that
/// should be gone would still be found.
Future<String> _contentOf(Uint8List bytes) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  try {
    return latin1.decode(await (await document.pageAt(1))!.contentPayload());
  } finally {
    await document.close();
  }
}

Future<PdfRenderedPage> _raster(Uint8List bytes) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  try {
    return await PdfPageRenderer.render((await document.pageAt(1))!,
        options: const PdfRenderOptions(dpi: _dpi));
  } finally {
    await document.close();
  }
}

/// How much of a pixel is inked, from 0 for untouched white to 1 for solid
/// black. Every test paints black on white, so the red channel says it all.
double _ink(PdfRenderedPage page, int x, int y) =>
    (255 - ((page.pixels[y * page.width + x] >> 16) & 0xff)) / 255;

/// The inked area in square points, by summing pixel coverage.
///
/// The renderer resolves coverage rather than testing pixel centres, so this
/// measures the real area of the shape and not a staircase approximation of
/// it: a 40-point square comes out at 1600 to within a fraction of a point.
double _inkArea(PdfRenderedPage page, {PdfRedactionArea? within}) {
  final left = within == null ? 0 : (within.left * _scale).round();
  final right = within == null ? page.width : (within.right * _scale).round();
  // The raster is y-down from the top of the page and user space is y-up.
  final top = within == null ? 0 : ((_pageSize - within.top) * _scale).round();
  final bottom = within == null
      ? page.height
      : ((_pageSize - within.bottom) * _scale).round();
  var total = 0.0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      total += _ink(page, x, y);
    }
  }
  return total / (_scale * _scale);
}

/// How two rasters differ outside [_area]: how many pixels changed at all,
/// the largest change to any one of them, and the total change as an area in
/// square points.
({int pixels, double worst, double area}) _differenceOutside(
    PdfRenderedPage before, PdfRenderedPage after) {
  final left = (_area.left * _scale).round();
  final right = (_area.right * _scale).round();
  final top = ((_pageSize - _area.top) * _scale).round();
  final bottom = ((_pageSize - _area.bottom) * _scale).round();
  var pixels = 0;
  var worst = 0.0;
  var total = 0.0;
  for (var y = 0; y < before.height; y++) {
    for (var x = 0; x < before.width; x++) {
      if (x >= left && x < right && y >= top && y < bottom) continue;
      final delta = (_ink(before, x, y) - _ink(after, x, y)).abs();
      if (delta > 1 / 255) pixels++;
      if (delta > worst) worst = delta;
      total += delta;
    }
  }
  return (pixels: pixels, worst: worst, area: total / (_scale * _scale));
}

/// Asserts the three things a clip has to get right at once, and returns the
/// rasters so a test can add its own.
///
/// The ink inside the area is gone, the ink outside it renders as it did
/// before, and the total area left is what the shape had minus what the
/// rectangle took from it.
///
/// "Renders as it did before" is exact for a shape with straight edges. For a
/// curve it cannot be: the rasteriser flattens curves to a 0.25-pixel
/// tolerance, and where a curve is cut decides where its facets land, so a
/// clipped arc lands a fraction of a pixel from where the whole one did. That
/// is the rasteriser's tolerance and not a change of shape, so a curved test
/// passes [curveBudget] — a bound on the total area the edge may shake by —
/// and the `a curve split in two already shakes the edge by as much` test
/// below shows the same numbers with no clipping involved at all.
Future<(PdfRenderedPage, PdfRenderedPage)> _expectClipped(String content,
    {double? curveBudget}) async {
  final source = await _page(content);
  final before = await _raster(source);
  final after = await _raster(await _redact(source));

  expect(_inkArea(after, within: _area), closeTo(0, 0.01),
      reason: 'no ink may be left inside the redaction area');
  final difference = _differenceOutside(before, after);
  if (curveBudget == null) {
    expect(difference.pixels, 0,
        reason: 'every pixel outside the area must render exactly as before');
  } else {
    expect(difference.worst, lessThan(0.3),
        reason: 'no pixel may move further than the flattening tolerance');
    expect(difference.area, lessThan(curveBudget),
        reason: 'the edge may shake, it may not move');
  }
  expect(_inkArea(after),
      closeTo(_inkArea(before) - _inkArea(before, within: _area), 0.05),
      reason: 'what is left must be the shape minus its part in the area');
  return (before, after);
}

/// The two parts of a cubic Bézier either side of [t], by De Casteljau.
///
/// The pair describes exactly the curve the one segment did, which is what
/// makes it a control for the rasterisation tests: whatever difference it
/// shows is the rasteriser's, because the geometry is the same curve.
List<List<double>> _splitAt(List<double> p, double t) {
  double lerp(double from, double to) => from + (to - from) * t;
  final a = [lerp(p[0], p[2]), lerp(p[1], p[3])];
  final b = [lerp(p[2], p[4]), lerp(p[3], p[5])];
  final c = [lerp(p[4], p[6]), lerp(p[5], p[7])];
  final d = [lerp(a[0], b[0]), lerp(a[1], b[1])];
  final e = [lerp(b[0], c[0]), lerp(b[1], c[1])];
  final f = [lerp(d[0], e[0]), lerp(d[1], e[1])];
  return [
    [p[0], p[1], a[0], a[1], d[0], d[1], f[0], f[1]],
    [f[0], f[1], e[0], e[1], c[0], c[1], p[6], p[7]],
  ];
}

/// A circle of radius 35 about the centre of the area, as the four cubics
/// every drawing program writes, with the 0.5522847 handle length.
const _radius = 35.0;
const _handle = 0.5522847498307936 * _radius;
final _circle = <List<double>>[
  [95, 60, 95, 60 + _handle, 60 + _handle, 95, 60, 95],
  [60, 95, 60 - _handle, 95, 25, 60 + _handle, 25, 60],
  [25, 60, 25, 60 - _handle, 60 - _handle, 25, 60, 25],
  [60, 25, 60 + _handle, 25, 95, 60 - _handle, 95, 60],
];

String _filled(List<List<double>> cubics) {
  final buffer = StringBuffer('0 g ${cubics.first[0]} ${cubics.first[1]} m ');
  for (final cubic in cubics) {
    buffer.write('${cubic[2]} ${cubic[3]} ${cubic[4]} ${cubic[5]} '
        '${cubic[6]} ${cubic[7]} c ');
  }
  return (buffer..write('h f\n')).toString();
}

void main() {
  group('the area left after a clip', () {
    test('a rectangle loses exactly its overlap, and nothing else', () async {
      // 60 by 60 from (20,20); a 40 by 40 corner of it is in the area.
      final (before, after) = await _expectClipped('0 g 20 20 60 60 re f\n');
      expect(_inkArea(before), closeTo(3600, 0.05));
      expect(_inkArea(after), closeTo(3600 - 1600, 0.05),
          reason: 'the analytic answer, not just a self-consistent one');
    });

    test('a triangle cut across one corner', () async {
      await _expectClipped('0 g 10 10 m 110 10 l 60 100 l h f\n');
    });

    test('a circle of Béziers keeps only what is outside the square', () async {
      // The circle is centred on the area and reaches past all four of its
      // edges, so every one of the four cubics has to be split.
      final (before, _) =
          await _expectClipped(_filled(_circle), curveBudget: 3);
      expect(_inkArea(before), closeTo(math.pi * _radius * _radius, 2),
          reason: 'the four-arc circle is within a tenth of a percent of πr²');
    });

    test('a curve split in two already shakes the edge by as much', () async {
      // The control for the curved tests above. Splitting each arc at t = 0.3
      // changes not one point of the circle — the two pieces trace the same
      // curve — and the raster still moves, because the rasteriser flattens
      // each Bézier to a quarter of a pixel and where a curve is cut decides
      // where the facets land. The numbers here are the ones the clipped
      // circle shows, so that difference is the rasteriser's and not a change
      // of shape.
      final whole = await _raster(await _page(_filled(_circle)));
      final split = await _raster(await _page(
          _filled([for (final cubic in _circle) ..._splitAt(cubic, 0.3)])));
      final difference = _differenceOutside(whole, split);
      expect(difference.pixels, greaterThan(1000),
          reason: 'identical geometry, and still a thousand pixels move');
      expect(difference.worst, lessThan(0.3));
      expect(difference.area, lessThan(3));
    });

    test('a shape that surrounds the area gets a hole, not a seam', () async {
      // The square's edges never come near the area, so nothing is cut: the
      // turn the square makes around the area is cancelled by a rectangle of
      // the opposite orientation instead.
      final (_, after) = await _expectClipped('0 g 10 10 100 100 re f\n');
      expect(_inkArea(after), closeTo(10000 - 1600, 0.05));
    });

    test('an area that swallows the shape leaves nothing behind', () async {
      final source = await _page('0 g 50 50 20 20 re f\n');
      final after = await _raster(await _redact(source));
      expect(_inkArea(after), closeTo(0, 0.01));
      expect(await _contentOf(await _redact(source)), isNot(contains('50 50')));
    });
  });

  group('the geometry is gone, not covered', () {
    test('no vertex inside the area survives in the stream', () async {
      // (44.5, 77.25) is inside the area, and both numbers appear nowhere
      // else; after the clip neither may be found anywhere in the stream.
      final source = await _page('0 g 10 10 m 100 10 l 44.5 77.25 l h f\n');
      final content = await _contentOf(await _redact(source));
      expect(content, isNot(contains('44.5')));
      expect(content, isNot(contains('77.25')));
      expect(content, contains('100 10 l'),
          reason: 'the part of the outline that is outside stays as it was');
    });

    test("a curve's control points inside the area go with it", () async {
      // The control points at (60,60) and (60,10) pull the curve through the
      // area; both are inside it in x, and the first in y as well.
      final source =
          await _page('0 g 10 10 m 60 60 60 10 110 10 c 110 110 l 10 110 l '
              'h f\n');
      final content = await _contentOf(await _redact(source));
      expect(content, isNot(contains('60 60')));
      final redacted = await _redact(source);
      expect(
          _inkArea(await _raster(redacted), within: _area), closeTo(0, 0.01));
    });
  });

  group('winding rules', () {
    test('even-odd keeps its hole and its verdict', () async {
      // A ring: the area sits in the hole, where even-odd paints nothing, so
      // there is nothing to remove and the path is left exactly as it was.
      final source = await _page('0 g 10 10 100 100 re 30 30 60 60 re f*\n');
      final before = await _raster(source);
      final content = await _contentOf(await _redact(source));
      expect(content, contains('30 30 60 60 re'),
          reason: 'a path with no ink in the area is not touched at all');
      final after = await _raster(await _redact(source));
      expect(_differenceOutside(before, after).pixels, 0);
      expect(_inkArea(after), closeTo(_inkArea(before), 0.05));
    });

    test('nonzero fills the same two rectangles solid, and loses the area',
        () async {
      // The same two rectangles under `f` wind twice, so the middle is solid
      // and the area has to be taken out of it.
      final (_, after) = await _expectClipped('0 g 10 10 100 100 re '
          '30 30 60 60 re f\n');
      expect(_inkArea(after), closeTo(10000 - 1600, 0.05));
    });

    test('even-odd loses only the part of the ring the area covers', () async {
      // Now the area straddles the ring's inner edge: part of it is on ink
      // and part in the hole.
      await _expectClipped('0 g 0 0 120 120 re 20 20 40 40 re f*\n');
    });
  });

  group('degenerate geometry', () {
    test('a curve tangent to an edge loses nothing to it', () async {
      // The controls at y = 50 put the cubic's highest point at exactly
      // (60, 40): it touches the bottom edge of the area and turns back. The
      // shape is outside the area, touching it at one point, so all of it has
      // to survive — a tangency read as a crossing would cut a bite out.
      final (before, after) = await _expectClipped(
          '0 g 10 10 m 10 50 110 50 110 10 c h f\n',
          curveBudget: 2);
      expect(_inkArea(after), closeTo(_inkArea(before), 0.05));
    });

    test('control points exactly on two corners of the area', () async {
      // Both handles sit on the boundary, at (40,40) and (80,40), which is
      // where the convex-hull test that decides "wholly one side" changes its
      // mind. The curve itself rises to y = 32.5, below the area.
      final (before, after) = await _expectClipped(
          '0 g 10 10 m 40 40 80 40 110 10 c h f\n',
          curveBudget: 2);
      expect(_inkArea(after), closeTo(_inkArea(before), 0.05));
    });

    test('a curve whose control point is inside the area, and whose ink is not',
        () async {
      // The handles at (50,45) and (70,45) are both strictly inside the area,
      // and the curve they pull only reaches y = 36.25, below it. The convex
      // hull says "meets" and the clip still has to hand the shape back
      // whole: the test is on the ink, not on the control polygon.
      final (before, after) = await _expectClipped(
          '0 g 10 10 m 50 45 70 45 110 10 c h f\n',
          curveBudget: 2);
      expect(_inkArea(after), closeTo(_inkArea(before), 0.05));
    });

    test('a vertex exactly on a corner of the area is not a crossing',
        () async {
      final source = await _page('0 g 10 10 m 40 40 l 10 90 l h f\n');
      final before = await _raster(source);
      final after = await _raster(await _redact(source));
      expect(_differenceOutside(before, after).pixels, 0);
      expect(_inkArea(after), closeTo(_inkArea(before), 0.05));
    });

    test('v and y are clipped as the curves they stand for', () async {
      // `v` borrows the current point for its first control point and `y` the
      // final point for its second (8.5.2.2). Writing each of them out as the
      // `c` it means has to give the same shape, before and after the clip.
      for (final pair in [
        ('10 10 m 70 90 110 10 v h f\n', '10 10 m 10 10 70 90 110 10 c h f\n'),
        ('10 10 m 30 90 110 10 y h f\n', '10 10 m 30 90 110 10 110 10 c h f\n'),
      ]) {
        final short =
            await _raster(await _redact(await _page('0 g ${pair.$1}')));
        final long =
            await _raster(await _redact(await _page('0 g ${pair.$2}')));
        expect(_inkArea(short, within: _area), closeTo(0, 0.02));
        expect(_inkArea(short), closeTo(_inkArea(long), 0.02),
            reason: 'shorthand and long form must clip alike: ${pair.$1}');
        expect(_differenceOutside(short, long).pixels, 0);
      }
    });

    test('a subpath that enters and leaves the area four times', () async {
      // A comb whose teeth reach up into the area and back out again.
      final buffer = StringBuffer('0 g 10 20 m ');
      for (var i = 0; i < 4; i++) {
        final x = 20.0 + i * 20;
        buffer.write('$x 20 l $x 60 l ${x + 8} 60 l ${x + 8} 20 l ');
      }
      buffer.write('110 20 l 110 10 l 10 10 l h f\n');
      await _expectClipped(buffer.toString());
    });

    test('a path that only touches the area from outside keeps its bytes',
        () async {
      final source = await _page('0 g 0 0 40 40 re f\n');
      expect(await _contentOf(await _redact(source)), contains('0 0 40 40 re'));
    });

    test('two areas are taken out one after the other', () async {
      const second =
          PdfRedactionArea(1, left: 0, bottom: 90, right: 120, top: 100);
      final source = await _page('0 g 10 10 100 100 re f\n');
      final before = await _raster(source);
      final after =
          await _raster(await _redact(source, areas: const [_area, second]));
      expect(_inkArea(after, within: _area), closeTo(0, 0.01));
      expect(_inkArea(after), closeTo(10000 - 1600 - 100 * 10, 0.1),
          reason: 'the square, less both rectangles it overlaps');
      expect(_inkArea(before), closeTo(10000, 0.05));
    });

    test('a path whose fill paints nothing still loses its coordinates',
        () async {
      // `n` outside a clipping path paints nothing at all, so the object can
      // go whole — and it must, or the coordinates stay in the file.
      final source = await _page('0 g 20 44.5 60 20 re n\n');
      expect(await _contentOf(await _redact(source)), isNot(contains('44.5')));
    });
  });

  group('under a transformation matrix', () {
    test(
        'a scaled and translated path is clipped in the page, not in its own '
        'numbers', () async {
      // The `cm` maps the unit square to 20..100 in both axes, so the shape
      // crosses the area although none of its own coordinates is anywhere
      // near it.
      final (_, after) =
          await _expectClipped('0 g q 80 0 0 80 20 20 cm 0 0 1 1 re f Q\n');
      expect(_inkArea(after), closeTo(80 * 80 - 1600, 0.05));
      final content =
          await _contentOf(await _redact(await _page('0 g q 80 0 0 80 20 20 '
              'cm 0 0 1 1 re f Q\n')));
      expect(content, contains('80 0 0 80 20 20 cm'),
          reason: 'the matrix is left in place and the geometry rewritten '
              'in the space it sets up');
      expect(content, contains('0.25'),
          reason: 'the area edge at 40 lands at 0.25 in the unit square');
    });

    test('a rotated path is clipped against the area as the page sees it',
        () async {
      // 45 degrees about the middle of the page: a square of side 40 becomes
      // a diamond whose corners reach into the area.
      const cos = 0.7071067811865476;
      await _expectClipped('0 g q $cos $cos ${-cos} $cos 60 -24.852814 cm '
          '20 20 60 60 re f Q\n');
    });
  });

  group('random paths', () {
    test('never leave ink in the area and never lose ink outside it', () async {
      // Shapes nobody would think to write by hand: mixed lines and curves,
      // self-intersecting as often as not, under both filling rules. The two
      // things that must hold for every one of them are that the area comes
      // out empty and that the area lost is exactly the area that was inside.
      final random = math.Random(20260913);
      for (var attempt = 0; attempt < 40; attempt++) {
        final buffer = StringBuffer('0 g ');
        double coordinate() => 5 + random.nextDouble() * 110;
        for (var subpath = 0; subpath < 1 + random.nextInt(2); subpath++) {
          buffer.write('${coordinate()} ${coordinate()} m ');
          final corners = 3 + random.nextInt(4);
          for (var i = 0; i < corners; i++) {
            if (random.nextBool()) {
              buffer.write('${coordinate()} ${coordinate()} l ');
            } else {
              buffer.write('${coordinate()} ${coordinate()} ${coordinate()} '
                  '${coordinate()} ${coordinate()} ${coordinate()} c ');
            }
          }
          buffer.write('h ');
        }
        buffer.write('${random.nextBool() ? 'f' : 'f*'}\n');
        final content = buffer.toString();

        final source = await _page(content);
        final before = await _raster(source);
        final after = await _raster(await _redact(source));
        expect(_inkArea(after, within: _area), closeTo(0, 0.02),
            reason: 'ink left inside the area by: $content');
        expect(_inkArea(after),
            closeTo(_inkArea(before) - _inkArea(before, within: _area), 0.5),
            reason: 'wrong area left by: $content');
      }
    });
  });

  group('what is still refused', () {
    test('a stroke that crosses an edge, because the pen overruns the cut',
        () async {
      await expectLater(
          _redact(await _page('0 g 2 w 10 60 m 110 60 l S\n')),
          throwsA(isA<UnsupportedError>().having(
              (e) => e.message, 'message', contains('stroking operators'))));
    });

    test('a fill and stroke together is refused for the stroke alone',
        () async {
      await expectLater(_redact(await _page('0 g 20 20 60 60 re B\n')),
          throwsUnsupportedError);
    });
  });
}
