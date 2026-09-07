import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/render/page_renderer.dart';
import 'package:test/test.dart';

/// A one-page document whose content stream is [content].
Future<CraftPdfDocument> _document(
  String content, {
  double width = 100,
  double height = 100,
  CraftPdfDictionary? resources,
  int rotate = 0,
}) async {
  final output = BytesBuilder(copy: false);
  final document =
      await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  page.pdfRepresentation()
    ..put(
        CraftPdfName.mediaBox, CraftPdfArray.fromDoubles([0, 0, width, height]))
    ..put(
        CraftPdfName.contents,
        CraftPdfStream.withBytes(
            Uint8List.fromList(latin1.encode(content)), 0));
  if (resources != null) {
    page.pdfRepresentation().put(CraftPdfName.resources, resources);
  }
  if (rotate != 0) {
    page
        .pdfRepresentation()
        .put(CraftPdfName('Rotate'), CraftPdfNumber.fromInt(rotate));
  }
  await document.close();

  return CraftPdfDocument.open(CraftPdfReader.fromBytes(output.takeBytes()));
}

Future<PdfRenderedPage> _render(
  String content, {
  double dpi = 72,
  double width = 100,
  double height = 100,
  CraftPdfDictionary? resources,
  int rotate = 0,
}) async {
  final document = await _document(content,
      width: width, height: height, resources: resources, rotate: rotate);
  try {
    return await PdfPageRenderer.render(
      (await document.pageAt(1))!,
      options: PdfRenderOptions(dpi: dpi),
    );
  } finally {
    await document.close();
  }
}

/// The pixel at (x, y) as (a, r, g, b).
({int a, int r, int g, int b}) _at(PdfRenderedPage page, int x, int y) {
  final word = page.pixels[y * page.width + x];
  return (
    a: (word >> 24) & 0xff,
    r: (word >> 16) & 0xff,
    g: (word >> 8) & 0xff,
    b: word & 0xff,
  );
}

void main() {
  group('PdfPageRenderer geometry', () {
    test('sizes the surface from the media box and the dpi', () async {
      final at72 = await _render('', width: 200, height: 100);
      expect(at72.width, equals(200));
      expect(at72.height, equals(100));

      final at144 = await _render('', width: 200, height: 100, dpi: 144);
      expect(at144.width, equals(400));
      expect(at144.height, equals(200));
    });

    test('paints the background where nothing is drawn', () async {
      final page = await _render('');

      final pixel = _at(page, 50, 50);
      expect(pixel.r, equals(255));
      expect(pixel.g, equals(255));
      expect(pixel.b, equals(255));
    });

    test('flips the y axis, since PDF is y-up and a raster is y-down',
        () async {
      // A black rectangle across the bottom 20 points of a 100-point page.
      final page = await _render('0 g 0 0 100 20 re f');

      // The bottom of the page is the bottom of the image.
      expect(_at(page, 50, 90).r, equals(0));
      expect(_at(page, 50, 10).r, equals(255));
    });

    test('swaps the surface dimensions for a 90 degree rotation', () async {
      final page = await _render('', width: 200, height: 100, rotate: 90);

      expect(page.width, equals(100));
      expect(page.height, equals(200));
    });
  });

  group('PdfPageRenderer paths', () {
    test('fills a rectangle in the colour that was set', () async {
      final page = await _render('1 0 0 rg 20 20 60 60 re f');

      final inside = _at(page, 50, 50);
      expect(inside.r, equals(255));
      expect(inside.g, equals(0));
      expect(inside.b, equals(0));
      expect(_at(page, 5, 5).r, equals(255)); // outside stays background
      expect(_at(page, 5, 5).g, equals(255));
    });

    test('honours the even-odd rule', () async {
      // A square with a square hole. Under even-odd the hole is empty; under
      // nonzero with both contours wound the same way it would be filled.
      const content = '0 g 10 10 80 80 re 30 30 40 40 re f*';
      final evenOdd = await _render(content);

      expect(_at(evenOdd, 15, 50).r, equals(0)); // the ring is filled
      expect(_at(evenOdd, 50, 50).r, equals(255)); // the hole is not
    });

    test('fills the same shape solid under the nonzero rule', () async {
      const content = '0 g 10 10 80 80 re 30 30 40 40 re f';
      final nonZero = await _render(content);

      expect(_at(nonZero, 50, 50).r, equals(0));
    });

    test('strokes a line at the width that was set', () async {
      final page = await _render('0 g 10 w 0 50 m 100 50 l S');

      // The line is 10 wide about y=50, which is row 50 in a 100-tall page.
      expect(_at(page, 50, 50).r, equals(0));
      expect(_at(page, 50, 5).r, equals(255));
    });

    test('applies the CTM to path coordinates', () async {
      // Translate by 50 then fill a unit-ish square at the origin.
      final page = await _render('0 g 1 0 0 1 50 50 cm 0 0 20 20 re f');

      // The square lands at user (50..70, 50..70), which is device rows 30..50.
      expect(_at(page, 60, 40).r, equals(0));
      expect(_at(page, 10, 40).r, equals(255));
    });

    test('restores the state saved by q on Q', () async {
      final page =
          await _render('0 g q 1 0 0 rg 0 0 50 100 re f Q 50 0 50 100 re f');

      expect(_at(page, 25, 50).r, equals(255)); // red half
      expect(_at(page, 25, 50).g, equals(0));
      expect(_at(page, 75, 50).r, equals(0)); // black half, colour restored
    });
  });

  group('PdfPageRenderer clipping', () {
    test('cuts a fill at the clip boundary', () async {
      // Clip to the left half, then fill the whole page.
      final page = await _render('0 g 0 0 50 100 re W n 0 0 100 100 re f');

      expect(_at(page, 25, 50).r, equals(0));
      expect(_at(page, 75, 50).r, equals(255),
          reason: 'the clip must actually cut, not merely reject');
    });

    test('restores the previous clip on Q', () async {
      final page = await _render('q 0 0 20 100 re W n Q 0 g 0 0 100 100 re f');

      // The clip was popped, so the fill covers everything.
      expect(_at(page, 90, 50).r, equals(0));
    });

    test('intersects nested clips', () async {
      final page = await _render(
          '0 0 60 100 re W n 40 0 60 100 re W n 0 g 0 0 100 100 re f');

      expect(_at(page, 50, 50).r, equals(0)); // in both
      expect(_at(page, 20, 50).r, equals(255)); // only in the first
      expect(_at(page, 80, 50).r, equals(255)); // only in the second
    });
  });

  group('PdfPageRenderer colour', () {
    test('reads gray, rgb and cmyk operators', () async {
      final gray = await _render('0.5 g 0 0 100 100 re f');
      expect(_at(gray, 50, 50).r, closeTo(128, 2));

      final cmyk = await _render('0 1 1 0 k 0 0 100 100 re f');
      expect(_at(cmyk, 50, 50).r, equals(255));
      expect(_at(cmyk, 50, 50).g, equals(0));
    });

    test('resolves a named colour space and its components', () async {
      final resources = CraftPdfDictionary()
        ..put(
            CraftPdfName('ColorSpace'),
            CraftPdfDictionary()
              ..put(CraftPdfName('CS0'), CraftPdfName('DeviceRGB')));

      final page = await _render('/CS0 cs 0 0 1 scn 0 0 100 100 re f',
          resources: resources);

      expect(_at(page, 50, 50).b, equals(255));
      expect(_at(page, 50, 50).r, equals(0));
    });

    test('applies ca from an ExtGState to a fill', () async {
      final resources = CraftPdfDictionary()
        ..put(
            CraftPdfName('ExtGState'),
            CraftPdfDictionary()
              ..put(
                  CraftPdfName('GS0'),
                  CraftPdfDictionary()
                    ..put(CraftPdfName('ca'), CraftPdfNumber(0.5))));

      final page =
          await _render('/GS0 gs 0 g 0 0 100 100 re f', resources: resources);

      // Half-transparent black over white is mid grey.
      expect(_at(page, 50, 50).r, closeTo(128, 4));
    });
  });

  group('PdfPageRenderer images', () {
    test('draws an image XObject into the unit square of the CTM', () async {
      // A 2x2 image: red, green / blue, white.
      final image = CraftPdfStream.withBytes(
          Uint8List.fromList([
            255, 0, 0, 0, 255, 0, //
            0, 0, 255, 255, 255, 255,
          ]),
          0)
        ..put(CraftPdfName.subtype, CraftPdfName('Image'))
        ..put(CraftPdfName.width, CraftPdfNumber.fromInt(2))
        ..put(CraftPdfName.height, CraftPdfNumber.fromInt(2))
        ..put(CraftPdfName('BitsPerComponent'), CraftPdfNumber.fromInt(8))
        ..put(CraftPdfName('ColorSpace'), CraftPdfName('DeviceRGB'));

      final resources = CraftPdfDictionary()
        ..put(CraftPdfName('XObject'),
            CraftPdfDictionary()..put(CraftPdfName('Im0'), image));

      final page =
          await _render('q 100 0 0 100 0 0 cm /Im0 Do Q', resources: resources);

      // Image row 0 is the top of the placement, so red is top-left.
      expect(_at(page, 25, 25).r, equals(255));
      expect(_at(page, 25, 25).g, equals(0));
      expect(_at(page, 75, 25).g, equals(255));
      expect(_at(page, 25, 75).b, equals(255));
      expect(page.report.imagesSkipped, isZero);
    });

    test('draws an inline image', () async {
      final page = await _render(
          'q 100 0 0 100 0 0 cm BI /W 1 /H 1 /BPC 8 /CS /G ID \x00 EI Q');

      expect(_at(page, 50, 50).r, equals(0));
      expect(page.report.imagesSkipped, isZero);
    });
  });

  group('PdfPageRenderer forms and reporting', () {
    test('runs a form XObject with its own matrix', () async {
      final form = CraftPdfStream.withBytes(
          Uint8List.fromList(latin1.encode('0 g 0 0 20 20 re f')), 0)
        ..put(CraftPdfName.subtype, CraftPdfName('Form'))
        ..put(CraftPdfName('BBox'), CraftPdfArray.fromDoubles([0, 0, 20, 20]))
        ..put(CraftPdfName('Matrix'),
            CraftPdfArray.fromDoubles([1, 0, 0, 1, 40, 40]));

      final resources = CraftPdfDictionary()
        ..put(CraftPdfName('XObject'),
            CraftPdfDictionary()..put(CraftPdfName('Fm0'), form));

      final page = await _render('/Fm0 Do', resources: resources);

      // The form draws at user (40..60), device rows 40..60.
      expect(_at(page, 50, 50).r, equals(0));
      expect(_at(page, 10, 90).r, equals(255));
    });

    test('reports text as skipped rather than pretending to draw it', () async {
      final page = await _render('BT /F1 12 Tf 10 50 Td (Hello) Tj ET');

      expect(page.report.glyphsSkipped, equals(1));
      expect(page.report.isComplete, isFalse);
      expect(page.report.toString(), contains('skipped'));
    });

    test('names an operator it does not implement', () async {
      final page = await _render('0 g /Sh0 sh 0 0 10 10 re f');

      expect(page.report.unsupportedOperators.keys, contains('sh'));
    });

    test('renders a complete page as a valid PNG', () async {
      final document = await _document('1 0 0 rg 10 10 80 80 re f');
      try {
        final png = await PdfPageRenderer.renderToPng(
            (await document.pageAt(1))!,
            options: const PdfRenderOptions(dpi: 72));

        expect(png.sublist(0, 8), equals([137, 80, 78, 71, 13, 10, 26, 10]));
        expect(png.length, greaterThan(100));
      } finally {
        await document.close();
      }
    });

    test('refuses a surface past the pixel budget', () async {
      final document = await _document('', width: 1000, height: 1000);
      try {
        final page = (await document.pageAt(1))!;
        expect(
          () => PdfPageRenderer.render(page,
              options: const PdfRenderOptions(dpi: 600, maxPixels: 1000)),
          throwsArgumentError,
        );
      } finally {
        await document.close();
      }
    });
  });
}
