import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// A one-page document whose content stream is [content].
Future<PdfDocument> _document(
  String content, {
  double width = 100,
  double height = 100,
  PdfDictionary? resources,
}) async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  page.pdfRepresentation()
    ..put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, width, height]))
    ..put(PdfName.contents,
        PdfStream.withBytes(Uint8List.fromList(latin1.encode(content)), 0));
  if (resources != null) {
    page.pdfRepresentation().put(PdfName.resources, resources);
  }
  await document.close();

  return PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
}

Future<PdfRenderedPage> _render(
  String content, {
  double width = 100,
  double height = 100,
  PdfDictionary? resources,
}) async {
  final document = await _document(content,
      width: width, height: height, resources: resources);
  try {
    return await PdfPageRenderer.render(
      (await document.pageAt(1))!,
      options: const PdfRenderOptions(dpi: 72),
    );
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

void _expectRgb(({int a, int r, int g, int b}) pixel, List<int> expected,
    {int tolerance = 1}) {
  expect(pixel.r, closeTo(expected[0], tolerance), reason: 'red');
  expect(pixel.g, closeTo(expected[1], tolerance), reason: 'green');
  expect(pixel.b, closeTo(expected[2], tolerance), reason: 'blue');
}

PdfDictionary _extGState(Map<String, PdfDictionary> states) {
  final dictionary = PdfDictionary();
  states.forEach((name, value) => dictionary.put(PdfName(name), value));
  return PdfDictionary()..put(PdfName('ExtGState'), dictionary);
}

PdfDictionary _blendState(String mode) =>
    PdfDictionary()..put(PdfName('BM'), PdfName(mode));

PdfStream _form(
  String content, {
  PdfDictionary? group,
  PdfDictionary? resources,
  List<double> bbox = const [0, 0, 100, 100],
}) {
  final stream =
      PdfStream.withBytes(Uint8List.fromList(latin1.encode(content)), 0)
        ..put(PdfName.subtype, PdfName('Form'))
        ..put(PdfName('BBox'), PdfArray.fromDoubles(bbox));
  if (group != null) stream.put(PdfName('Group'), group);
  if (resources != null) stream.put(PdfName.resources, resources);
  return stream;
}

PdfDictionary _transparencyGroup({bool isolated = false, bool knockout = false}) =>
    PdfDictionary()
      ..put(PdfName.s, PdfName('Transparency'))
      ..put(PdfName('I'), PdfBoolean(isolated))
      ..put(PdfName('K'), PdfBoolean(knockout));

void main() {
  group('blend modes', () {
    // Backdrop 0.8 0.4 0.2 over source 0.25 grey, both fully opaque, so the
    // compositing formula of clause 11.3.6 collapses to B(Cb, Cs) itself.
    Future<({int a, int r, int g, int b})> blended(String mode) async {
      final page = await _render(
        '0.8 0.4 0.2 rg 0 0 100 100 re f /BM gs 0.25 g 20 20 60 60 re f',
        resources: _extGState({'BM': _blendState(mode)}),
      );
      return _at(page, 50, 50);
    }

    test('Normal leaves the source colour alone', () async {
      _expectRgb(await blended('Normal'), [64, 64, 64]);
    });

    test('Compatible is Normal', () async {
      _expectRgb(await blended('Compatible'), [64, 64, 64]);
    });

    test('Multiply darkens towards the product of the two colours', () async {
      _expectRgb(await blended('Multiply'), [51, 26, 13]);
    });

    test('Screen lightens towards the product of the complements', () async {
      _expectRgb(await blended('Screen'), [217, 140, 102]);
    });

    test('Overlay switches on the backdrop', () async {
      _expectRgb(await blended('Overlay'), [179, 51, 26]);
    });

    test('Darken keeps the darker component', () async {
      _expectRgb(await blended('Darken'), [64, 64, 51]);
    });

    test('Lighten keeps the lighter component', () async {
      _expectRgb(await blended('Lighten'), [204, 102, 64]);
    });

    test('ColorDodge brightens the backdrop and saturates at white', () async {
      _expectRgb(await blended('ColorDodge'), [255, 136, 68]);
    });

    test('ColorBurn darkens the backdrop and saturates at black', () async {
      _expectRgb(await blended('ColorBurn'), [52, 0, 0]);
    });

    test('HardLight switches on the source', () async {
      _expectRgb(await blended('HardLight'), [102, 51, 26]);
    });

    test('SoftLight darkens gently below half', () async {
      _expectRgb(await blended('SoftLight'), [184, 72, 31]);
    });

    test('Difference is the absolute difference', () async {
      _expectRgb(await blended('Difference'), [140, 38, 13]);
    });

    test('Exclusion is a lower-contrast Difference', () async {
      _expectRgb(await blended('Exclusion'), [166, 115, 89]);
    });

    test('SoftLight uses the cubic below a quarter, not a plain root',
        () async {
      // With cs above a half the spec substitutes D(x) = ((16x-12)x+4)x for
      // sqrt(x) when x <= 0.25.
      final page = await _render(
        '0.1 g 0 0 100 100 re f /BM gs 1 g 20 20 60 60 re f',
        resources: _extGState({'BM': _blendState('SoftLight')}),
      );
      // cb = 26/255 = 0.10196 and cs = 1, so the result is exactly D(cb):
      // ((16*0.10196 - 12)*0.10196 + 4)*0.10196 = 0.3000, which is 76.5 of
      // 255. Taking the root instead would give sqrt(0.10196) = 0.3193, or
      // 81 — close enough that only an exact expectation separates the two.
      _expectRgb(_at(page, 50, 50), [77, 77, 77]);
    });

    test('an unknown blend mode is reported rather than silently applied',
        () async {
      final page = await _render(
        '/BM gs 0 g 20 20 60 60 re f',
        resources: _extGState({'BM': _blendState('Gouache')}),
      );
      expect(page.report.unsupportedOperators.keys, contains('gs:BM/Gouache'));
    });

    test('an array of blend modes selects the first one implemented',
        () async {
      final state = PdfDictionary()
        ..put(
            PdfName('BM'),
            PdfArray()
              ..add(PdfName('Gouache'))
              ..add(PdfName('Multiply')));
      final page = await _render(
        '0.8 0.4 0.2 rg 0 0 100 100 re f /BM gs 0.25 g 20 20 60 60 re f',
        resources: _extGState({'BM': state}),
      );
      _expectRgb(_at(page, 50, 50), [51, 26, 13]);
    });

    test('a blend mode is undone by Q along with the rest of the state',
        () async {
      final page = await _render(
        '0.8 0.4 0.2 rg 0 0 100 100 re f '
        'q /BM gs Q 0.25 g 20 20 60 60 re f',
        resources: _extGState({'BM': _blendState('Multiply')}),
      );
      _expectRgb(_at(page, 50, 50), [64, 64, 64]);
    });
  });

  group('non-separable blend modes', () {
    // Backdrop 0.8 0.4 0.2, source 1 0.5 0, both opaque. The four modes of
    // Table 137 each keep a different pair of hue, saturation and luminosity.
    Future<({int a, int r, int g, int b})> blended(String mode) async {
      final page = await _render(
        '0.8 0.4 0.2 rg 0 0 100 100 re f /BM gs 1 0.5 0 rg 20 20 60 60 re f',
        resources: _extGState({'BM': _blendState(mode)}),
      );
      return _at(page, 50, 50);
    }

    test('Hue takes the source hue with the backdrop saturation and luminosity',
        () async {
      _expectRgb(await blended('Hue'), [189, 113, 36]);
    });

    test('Saturation takes the source saturation only', () async {
      _expectRgb(await blended('Saturation'), [255, 85, 1]);
    });

    test('Color keeps the backdrop luminosity', () async {
      _expectRgb(await blended('Color'), [213, 107, 0]);
    });

    test('Luminosity keeps the backdrop hue and saturation', () async {
      _expectRgb(await blended('Luminosity'), [229, 127, 76]);
    });

    test('Saturation over a grey backdrop changes nothing', () async {
      // Clause 11.3.5, Table 137, NOTE 2: a backdrop with no saturation has
      // nothing for the source saturation to stretch.
      final page = await _render(
        '0.25 g 0 0 100 100 re f /BM gs 1 0 0 rg 20 20 60 60 re f',
        resources: _extGState({'BM': _blendState('Saturation')}),
      );
      _expectRgb(_at(page, 50, 50), [64, 64, 64]);
    });
  });

  group('transparency groups', () {
    test('applies the constant alpha to the group, not to each object',
        () async {
      // Two opaque overlapping squares at 50% alpha. Painted separately the
      // overlap would compound to 25%; as a group the alpha applies once.
      final resources = _extGState({'A': PdfDictionary()
        ..put(PdfName('ca'), PdfNumber(0.5))})
        ..put(
            PdfName('XObject'),
            PdfDictionary()
              ..put(
                  PdfName('Fm'),
                  _form('0 g 10 10 50 50 re f 30 30 50 50 re f',
                      group: _transparencyGroup(isolated: true))));

      final page = await _render('/A gs /Fm Do', resources: resources);

      final single = _at(page, 20, 80); // only the first square
      final overlap = _at(page, 50, 50); // both squares
      _expectRgb(single, [128, 128, 128]);
      _expectRgb(overlap, [128, 128, 128]);
    });

    test('an isolated group does not blend with the page behind it', () async {
      final inner = _extGState({'M': _blendState('Multiply')});
      final resources = _extGState({})
        ..put(
            PdfName('XObject'),
            PdfDictionary()
              ..put(
                  PdfName('Fm'),
                  _form('/M gs 0.5 g 20 20 60 60 re f',
                      group: _transparencyGroup(isolated: true),
                      resources: inner)));

      final page = await _render('0.5 g 0 0 100 100 re f /Fm Do',
          resources: resources);

      // Multiply inside an isolated group sees a transparent backdrop, so it
      // contributes the source colour unchanged.
      _expectRgb(_at(page, 50, 50), [128, 128, 128]);
    });

    test('a non-isolated group blends with the page behind it', () async {
      final inner = _extGState({'M': _blendState('Multiply')});
      final resources = _extGState({})
        ..put(
            PdfName('XObject'),
            PdfDictionary()
              ..put(
                  PdfName('Fm'),
                  _form('/M gs 0.5 g 20 20 60 60 re f',
                      group: _transparencyGroup(isolated: false),
                      resources: inner)));

      final page = await _render('0.5 g 0 0 100 100 re f /Fm Do',
          resources: resources);

      // 0.50196 * 0.50196 = 0.25196.
      _expectRgb(_at(page, 50, 50), [64, 64, 64]);
    });

    test('a knockout group lets the topmost object win', () async {
      final inner = _extGState({'A': PdfDictionary()
        ..put(PdfName('ca'), PdfNumber(0.5))});
      const content = '/A gs 1 0 0 rg 10 10 50 50 re f '
          '0 0 1 rg 30 30 50 50 re f';

      final knockout = _extGState({})
        ..put(
            PdfName('XObject'),
            PdfDictionary()
              ..put(
                  PdfName('Fm'),
                  _form(content,
                      group: _transparencyGroup(isolated: true, knockout: true),
                      resources: inner)));
      final normal = _extGState({})
        ..put(
            PdfName('XObject'),
            PdfDictionary()
              ..put(
                  PdfName('Fm'),
                  _form(content,
                      group:
                          _transparencyGroup(isolated: true, knockout: false),
                      resources: inner)));

      final knockedOut =
          _at(await _render('/Fm Do', resources: knockout), 50, 50);
      final stacked = _at(await _render('/Fm Do', resources: normal), 50, 50);

      // Knocked out, the overlap is the blue square over the group's
      // transparent initial backdrop; stacked, the red square still shows
      // through it.
      _expectRgb(knockedOut, [127, 127, 255]);
      _expectRgb(stacked, [127, 63, 191]);
      expect(knockedOut.g, greaterThan(stacked.g + 30));
    });

    test('a soft mask applies to the finished group, not to its elements',
        () async {
      // The group paints the same square twice. With the mask applied per
      // object the two would compound; applied to the group they do not.
      final maskGroup = _form('1 g 0 0 100 100 re f',
          group: PdfDictionary()
            ..put(PdfName.s, PdfName('Transparency'))
            ..put(PdfName('CS'), PdfName('DeviceGray')));
      final softMask = PdfDictionary()
        ..put(PdfName.s, PdfName('Luminosity'))
        ..put(PdfName('G'), maskGroup);

      final resources = _extGState({
        'S': PdfDictionary()..put(PdfName('SMask'), softMask),
      })
        ..put(
            PdfName('XObject'),
            PdfDictionary()
              ..put(
                  PdfName('Fm'),
                  _form('0 g 20 20 60 60 re f 20 20 60 60 re f',
                      group: _transparencyGroup(isolated: true))));

      final page = await _render('/S gs /Fm Do', resources: resources);
      // A fully luminous mask leaves the group untouched.
      _expectRgb(_at(page, 50, 50), [0, 0, 0]);
    });

    test('a plain form XObject without a group still draws in place', () async {
      final resources = PdfDictionary()
        ..put(PdfName('XObject'),
            PdfDictionary()..put(PdfName('Fm'), _form('0 g 20 20 60 60 re f')));

      final page = await _render('/Fm Do', resources: resources);
      _expectRgb(_at(page, 50, 50), [0, 0, 0]);
      _expectRgb(_at(page, 5, 5), [255, 255, 255]);
    });

    test('the group is clipped to its bounding box', () async {
      final resources = PdfDictionary()
        ..put(
            PdfName('XObject'),
            PdfDictionary()
              ..put(
                  PdfName('Fm'),
                  _form('0 g 0 0 100 100 re f',
                      group: _transparencyGroup(isolated: true),
                      bbox: const [0, 0, 50, 50])));

      final page = await _render('/Fm Do', resources: resources);
      // The box covers the lower-left quarter of the page, which is the
      // bottom left of the raster.
      _expectRgb(_at(page, 25, 75), [0, 0, 0]);
      _expectRgb(_at(page, 75, 25), [255, 255, 255]);
    });

    test('a blend mode set outside the group applies to the whole group',
        () async {
      final resources = _extGState({'M': _blendState('Difference')})
        ..put(
            PdfName('XObject'),
            PdfDictionary()
              ..put(
                  PdfName('Fm'),
                  _form('0.25 g 20 20 60 60 re f',
                      group: _transparencyGroup(isolated: true))));

      final page = await _render(
          '0.8 0.4 0.2 rg 0 0 100 100 re f /M gs /Fm Do',
          resources: resources);

      _expectRgb(_at(page, 50, 50), [140, 38, 13]);
    });
  });

  group('function-based shading', () {
    /// A 2-in 3-out PostScript function that ignores y and returns x as a
    /// grey, i.e. a horizontal ramp across the shading's domain.
    PdfStream rampFunction() =>
        PdfStream.withBytes(Uint8List.fromList(latin1.encode('{ pop dup dup }')),
            0)
          ..put(PdfName('FunctionType'), PdfNumber.fromInt(4))
          ..put(PdfName('Domain'), PdfArray.fromDoubles([0, 1, 0, 1]))
          ..put(PdfName('Range'), PdfArray.fromDoubles([0, 1, 0, 1, 0, 1]));

    test('paints a type 1 shading through its function and matrix', () async {
      final shading = PdfDictionary()
        ..put(PdfName.shadingType, PdfNumber.fromInt(1))
        ..put(PdfName.colorSpace, PdfName('DeviceRGB'))
        ..put(PdfName('Domain'), PdfArray.fromDoubles([0, 1, 0, 1]))
        ..put(PdfName.matrix, PdfArray.fromDoubles([100, 0, 0, 100, 0, 0]))
        ..put(PdfName.function, rampFunction());

      final resources = PdfDictionary()
        ..put(PdfName.shading, PdfDictionary()..put(PdfName('Sh'), shading));

      final page = await _render('/Sh sh', resources: resources);

      // The matrix maps the unit domain onto the whole 100-point page, so the
      // grey at device x is x/100.
      expect(_at(page, 10, 50).r, closeTo(26, 2));
      expect(_at(page, 50, 50).r, closeTo(128, 2));
      expect(_at(page, 90, 50).r, closeTo(230, 2));
      expect(page.report.unsupportedOperators, isEmpty);
    });

    test('leaves points outside the domain unpainted', () async {
      final shading = PdfDictionary()
        ..put(PdfName.shadingType, PdfNumber.fromInt(1))
        ..put(PdfName.colorSpace, PdfName('DeviceRGB'))
        ..put(PdfName('Domain'), PdfArray.fromDoubles([0, 1, 0, 1]))
        ..put(PdfName.matrix, PdfArray.fromDoubles([50, 0, 0, 50, 0, 0]))
        ..put(PdfName.function, rampFunction());

      final resources = PdfDictionary()
        ..put(PdfName.shading, PdfDictionary()..put(PdfName('Sh'), shading));

      final page = await _render('/Sh sh', resources: resources);

      // The domain covers the lower-left 50x50 points only.
      expect(_at(page, 25, 75).r, closeTo(128, 3));
      _expectRgb(_at(page, 75, 25), [255, 255, 255]);
    });

    test('paints the background outside the domain when one is given',
        () async {
      final shading = PdfDictionary()
        ..put(PdfName.shadingType, PdfNumber.fromInt(1))
        ..put(PdfName.colorSpace, PdfName('DeviceRGB'))
        ..put(PdfName.matrix, PdfArray.fromDoubles([50, 0, 0, 50, 0, 0]))
        ..put(PdfName('Background'), PdfArray.fromDoubles([0, 0, 1]))
        ..put(PdfName.function, rampFunction());

      final resources = PdfDictionary()
        ..put(PdfName.shading, PdfDictionary()..put(PdfName('Sh'), shading));

      final page = await _render('/Sh sh', resources: resources);
      _expectRgb(_at(page, 75, 25), [0, 0, 255]);
    });

    test('a type 1 shading accepts one function per colour component',
        () async {
      PdfStream component(String body) =>
          PdfStream.withBytes(Uint8List.fromList(latin1.encode(body)), 0)
            ..put(PdfName('FunctionType'), PdfNumber.fromInt(4))
            ..put(PdfName('Domain'), PdfArray.fromDoubles([0, 1, 0, 1]))
            ..put(PdfName('Range'), PdfArray.fromDoubles([0, 1]));

      final shading = PdfDictionary()
        ..put(PdfName.shadingType, PdfNumber.fromInt(1))
        ..put(PdfName.colorSpace, PdfName('DeviceRGB'))
        ..put(PdfName.matrix, PdfArray.fromDoubles([100, 0, 0, 100, 0, 0]))
        ..put(
            PdfName.function,
            PdfArray()
              ..add(component('{ pop }'))
              ..add(component('{ exch pop }'))
              ..add(component('{ pop pop 0 }')));

      final resources = PdfDictionary()
        ..put(PdfName.shading, PdfDictionary()..put(PdfName('Sh'), shading));

      final page = await _render('/Sh sh', resources: resources);

      // Red grows to the right, green upwards, blue stays out.
      final pixel = _at(page, 75, 25);
      expect(pixel.r, closeTo(191, 3));
      expect(pixel.g, closeTo(191, 3));
      expect(pixel.b, closeTo(0, 3));
    });

    test('honours the BBox a shading dictionary may carry', () async {
      final shading = PdfDictionary()
        ..put(PdfName.shadingType, PdfNumber.fromInt(1))
        ..put(PdfName.colorSpace, PdfName('DeviceRGB'))
        ..put(PdfName.matrix, PdfArray.fromDoubles([100, 0, 0, 100, 0, 0]))
        ..put(PdfName.bBox, PdfArray.fromDoubles([0, 0, 50, 100]))
        ..put(PdfName.function, rampFunction());

      final resources = PdfDictionary()
        ..put(PdfName.shading, PdfDictionary()..put(PdfName('Sh'), shading));

      final page = await _render('/Sh sh', resources: resources);
      expect(_at(page, 25, 50).r, closeTo(64, 3));
      _expectRgb(_at(page, 75, 50), [255, 255, 255]);
    });
  });

  group('colour key masking', () {
    test('does not paint samples inside the masked ranges', () async {
      // A 2x2 image: red, green / blue, white. The mask covers pure red only.
      final image = PdfStream.withBytes(
          Uint8List.fromList([
            255, 0, 0, 0, 255, 0, //
            0, 0, 255, 255, 255, 255,
          ]),
          0)
        ..put(PdfName.subtype, PdfName('Image'))
        ..put(PdfName.width, PdfNumber.fromInt(2))
        ..put(PdfName.height, PdfNumber.fromInt(2))
        ..put(PdfName('BitsPerComponent'), PdfNumber.fromInt(8))
        ..put(PdfName('ColorSpace'), PdfName('DeviceRGB'))
        ..put(PdfName('Mask'),
            PdfArray.fromDoubles([255, 255, 0, 0, 0, 0]));

      final resources = PdfDictionary()
        ..put(PdfName('XObject'), PdfDictionary()..put(PdfName('Im0'), image));

      final page =
          await _render('q 100 0 0 100 0 0 cm /Im0 Do Q', resources: resources);

      // The red sample is masked out, so the page shows through.
      _expectRgb(_at(page, 25, 25), [255, 255, 255]);
      _expectRgb(_at(page, 75, 25), [0, 255, 0]);
      _expectRgb(_at(page, 25, 75), [0, 0, 255]);
      expect(page.report.imagesSkipped, isZero);
    });

    test('a range that matches nothing leaves the image intact', () async {
      final image = PdfStream.withBytes(
          Uint8List.fromList([255, 0, 0]), 0)
        ..put(PdfName.subtype, PdfName('Image'))
        ..put(PdfName.width, PdfNumber.fromInt(1))
        ..put(PdfName.height, PdfNumber.fromInt(1))
        ..put(PdfName('BitsPerComponent'), PdfNumber.fromInt(8))
        ..put(PdfName('ColorSpace'), PdfName('DeviceRGB'))
        ..put(PdfName('Mask'), PdfArray.fromDoubles([0, 10, 0, 10, 0, 10]));

      final resources = PdfDictionary()
        ..put(PdfName('XObject'), PdfDictionary()..put(PdfName('Im0'), image));

      final page =
          await _render('q 100 0 0 100 0 0 cm /Im0 Do Q', resources: resources);
      _expectRgb(_at(page, 50, 50), [255, 0, 0]);
    });

    test('masks an indexed image by palette index', () async {
      // Two palette entries, red and green; index 0 is masked out.
      final palette = PdfStream.withBytes(
          Uint8List.fromList([255, 0, 0, 0, 255, 0]), 0);
      final space = PdfArray()
        ..add(PdfName('Indexed'))
        ..add(PdfName('DeviceRGB'))
        ..add(PdfNumber.fromInt(1))
        ..add(palette);

      final image = PdfStream.withBytes(Uint8List.fromList([0x40]), 0)
        ..put(PdfName.subtype, PdfName('Image'))
        ..put(PdfName.width, PdfNumber.fromInt(2))
        ..put(PdfName.height, PdfNumber.fromInt(1))
        ..put(PdfName('BitsPerComponent'), PdfNumber.fromInt(1))
        ..put(PdfName('ColorSpace'), space)
        ..put(PdfName('Mask'), PdfArray.fromDoubles([0, 0]));

      final resources = PdfDictionary()
        ..put(PdfName('XObject'), PdfDictionary()..put(PdfName('Im0'), image));

      final page =
          await _render('q 100 0 0 100 0 0 cm /Im0 Do Q', resources: resources);

      // 0x40 is bits 0 then 1: index 0 (masked) then index 1 (green).
      _expectRgb(_at(page, 25, 50), [255, 255, 255]);
      _expectRgb(_at(page, 75, 50), [0, 255, 0]);
    });
  });
}
