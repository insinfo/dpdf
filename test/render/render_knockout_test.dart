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

Future<PdfRenderedPage> _render(String content,
    {PdfDictionary? resources}) async {
  final document = await _document(content, resources: resources);
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

PdfDictionary _group({required bool isolated, required bool knockout}) =>
    PdfDictionary()
      ..put(PdfName.s, PdfName('Transparency'))
      ..put(PdfName('I'), PdfBoolean(isolated))
      ..put(PdfName('K'), PdfBoolean(knockout));

/// A `/Resources` dictionary holding a half-opaque graphics state named `A`
/// plus the named XObjects.
PdfDictionary _resources(Map<String, PdfStream> xobjects) {
  final states = PdfDictionary()
    ..put(PdfName('A'), PdfDictionary()..put(PdfName('ca'), PdfNumber(0.5)));
  final objects = PdfDictionary();
  xobjects.forEach((name, stream) => objects.put(PdfName(name), stream));
  return PdfDictionary()
    ..put(PdfName('ExtGState'), states)
    ..put(PdfName('XObject'), objects);
}

/// Two overlapping half-opaque squares, red then blue.
const _twoSquares = '/A gs 1 0 0 rg 10 10 50 50 re f '
    '0 0 1 rg 30 30 50 50 re f';

/// The same pair drawn as 1x1 inline images rather than as paths.
const _twoImages = '/A gs '
    'q 50 0 0 50 10 10 cm BI /W 1 /H 1 /CS /RGB /BPC 8 ID \xff\x00\x00 EI Q '
    'q 50 0 0 50 30 30 cm BI /W 1 /H 1 /CS /RGB /BPC 8 ID \x00\x00\xff EI Q';

void main() {
  group('knockout groups, clauses 11.4.5 and 11.4.6', () {
    test('a non-isolated knockout group knocks out against the page', () async {
      // The group's initial backdrop is what the page already holds, so the
      // blue square composites with the grey page rather than with the red
      // square it covers.
      Future<({int a, int r, int g, int b})> pixel(bool knockout) async {
        final page = await _render(
          '0.8 g 0 0 100 100 re f /Fm Do',
          resources: _resources({
            'Fm': _form(_twoSquares,
                group: _group(isolated: false, knockout: knockout),
                resources: _resources(const {})),
          }),
        );
        return _at(page, 50, 50);
      }

      // 0.5 blue over 0.8 grey.
      _expectRgb(await pixel(true), [102, 102, 230]);
      // 0.5 blue over (0.5 red over 0.8 grey).
      _expectRgb(await pixel(false), [115, 51, 179]);
    });

    test('images knock each other out, not only paths', () async {
      Future<({int a, int r, int g, int b})> pixel(bool knockout) async {
        final page = await _render(
          '/Fm Do',
          resources: _resources({
            'Fm': _form(_twoImages,
                group: _group(isolated: true, knockout: knockout),
                resources: _resources(const {})),
          }),
        );
        return _at(page, 50, 50);
      }

      _expectRgb(await pixel(true), [127, 127, 255], tolerance: 2);
      _expectRgb(await pixel(false), [127, 63, 191], tolerance: 2);
    });

    test('a nested group counts as one object of the knockout group', () async {
      // Clause 11.4.6 composites whole objects, and a transparency group is
      // one object: the blue group must erase the red square underneath it
      // rather than blend with it.
      Future<({int a, int r, int g, int b})> pixel(bool knockout) async {
        final inner = _form('0 0 1 rg 30 30 50 50 re f',
            group: _group(isolated: true, knockout: false));
        final outer = _form(
          '/A gs 1 0 0 rg 10 10 50 50 re f /In Do',
          group: _group(isolated: true, knockout: knockout),
          resources: _resources({'In': inner}),
        );
        final page =
            await _render('/Fm Do', resources: _resources({'Fm': outer}));
        return _at(page, 50, 50);
      }

      _expectRgb(await pixel(true), [127, 127, 255]);
      _expectRgb(await pixel(false), [127, 63, 191]);
    });

    test('a knockout group survives a text object inside it', () async {
      // `ET` ends the text-knockout scope of clause 9.3.8, which must not
      // take the enclosing group's knockout backdrop with it.
      Future<({int a, int r, int g, int b})> pixel(bool knockout) async {
        final page = await _render(
          '/Fm Do',
          resources: _resources({
            'Fm': _form(
                '/A gs 1 0 0 rg 10 10 50 50 re f BT ET '
                '0 0 1 rg 30 30 50 50 re f',
                group: _group(isolated: true, knockout: knockout),
                resources: _resources(const {})),
          }),
        );
        return _at(page, 50, 50);
      }

      _expectRgb(await pixel(true), [127, 127, 255]);
      _expectRgb(await pixel(false), [127, 63, 191]);
    });

    test('knockout and non-knockout agree when nothing is transparent',
        () async {
      // The check the briefing asks for in reverse: at alpha 1 the two rules
      // cannot differ, so a difference here would mean the knockout path is
      // doing something it should not.
      const content = '1 0 0 rg 10 10 50 50 re f 0 0 1 rg 30 30 50 50 re f';
      Future<Uint32List> pixels(bool knockout) async {
        final page = await _render(
          '/Fm Do',
          resources: _resources({
            'Fm': _form(content,
                group: _group(isolated: true, knockout: knockout)),
          }),
        );
        return page.pixels;
      }

      expect(await pixels(true), equals(await pixels(false)));
    });

    test('a knockout group restores the enclosing one when it ends', () async {
      // A knockout group nested inside another: after the inner one finishes,
      // the outer group must still knock out its own remaining objects.
      final inner = _form('0 1 0 rg 0 0 20 20 re f',
          group: _group(isolated: true, knockout: true));
      final outer = _form(
        '/A gs 1 0 0 rg 10 10 50 50 re f /In Do 0 0 1 rg 30 30 50 50 re f',
        group: _group(isolated: true, knockout: true),
        resources: _resources({'In': inner}),
      );
      final page =
          await _render('/Fm Do', resources: _resources({'Fm': outer}));

      // The blue square, last of the outer group, still knocks the red one
      // out where they overlap.
      _expectRgb(_at(page, 50, 50), [127, 127, 255]);
    });
  });
}
