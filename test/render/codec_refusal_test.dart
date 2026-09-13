import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/render/page_renderer.dart';
import 'package:test/test.dart';

/// A one-page document that draws a single image XObject filtered by [filter].
///
/// [data] is deliberately something the codec cannot read.
Future<PdfDocument> _pageWithImage(String filter, List<int> data) async {
  final output = BytesBuilder(copy: false);
  final document = await PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();

  final image = PdfStream.withBytes(Uint8List.fromList(data), 0)
    ..put(PdfName.type, PdfName('XObject'))
    ..put(PdfName.subtype, PdfName('Image'))
    ..put(PdfName('Width'), PdfNumber.fromInt(8))
    ..put(PdfName('Height'), PdfNumber.fromInt(8))
    ..put(PdfName('BitsPerComponent'), PdfNumber.fromInt(8))
    ..put(PdfName('ColorSpace'), PdfName('DeviceRGB'))
    ..put(PdfName.filter, PdfName(filter));

  page.pdfRepresentation()
    ..put(PdfName.mediaBox, PdfArray.fromDoubles([0, 0, 100, 100]))
    ..put(
        PdfName.resources,
        PdfDictionary()
          ..put(PdfName('XObject'), PdfDictionary()..put(PdfName('Im0'), image)))
    ..put(
        PdfName.contents,
        PdfStream.withBytes(
            Uint8List.fromList(
                latin1.encode('q 80 0 0 80 10 10 cm /Im0 Do Q '
                    '1 0 0 RG 4 w 5 5 m 95 95 l S')),
            0));
  await document.close();
  return PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
}

Future<PdfRenderedPage> _render(PdfDocument document) async {
  try {
    return await PdfPageRenderer.render((await document.pageAt(1))!);
  } finally {
    await document.close();
  }
}

void main() {
  group('a codec that refuses an image does not take the page with it', () {
    // The render report exists to name skipped work instead of pretending the
    // page came out whole. A codec refusing one image has to reach that
    // report, not escape as an exception through the renderer: one unreadable
    // image in a scanned document would otherwise cost every other page.

    test('an unreadable JPEG is counted, not thrown', () async {
      // No SOI marker, so `JpegDecoder` refuses it outright.
      final document = await _pageWithImage(
          'DCTDecode', List<int>.filled(64, 0x41));

      final page = await _render(document);

      expect(page.report.imagesSkipped, equals(1));
    });

    test('an unreadable JPEG 2000 image is counted, not thrown', () async {
      // Neither a JP2 signature box nor an SOC marker.
      final document = await _pageWithImage(
          'JPXDecode', List<int>.filled(64, 0x42));

      final page = await _render(document);

      expect(page.report.imagesSkipped, equals(1));
    });

    test('a truncated JPEG 2000 codestream is counted, not thrown', () async {
      // Starts like a real codestream (SOC + SIZ) and then stops, which is the
      // truncation case rather than the "not a JPEG 2000 file" case.
      final document = await _pageWithImage('JPXDecode',
          [0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x2F, 0x00, 0x00]);

      final page = await _render(document);

      expect(page.report.imagesSkipped, equals(1));
    });

    test('the rest of the page still renders', () async {
      // The point of not throwing: everything that is not the broken image
      // still reaches the canvas. The content stream draws a red diagonal
      // after the image, and it has to be there.
      final document = await _pageWithImage(
          'JPXDecode', List<int>.filled(64, 0x42));

      final page = await _render(document);

      // Count the diagonal rather than probe one coordinate: what matters is
      // that the stroke reached the canvas, not where antialiasing put its
      // centre.
      var painted = 0;
      for (final pixel in page.pixels) {
        final red = (pixel >> 16) & 0xFF;
        final green = (pixel >> 8) & 0xFF;
        final blue = pixel & 0xFF;
        if (red > 200 && green < 80 && blue < 80) painted++;
      }
      expect(painted, greaterThan(100),
          reason: 'a diagonal vermelha desenhada depois da imagem que falhou '
              'tem de chegar na tela');
    });
  });
}
