import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// The rectangle every test redacts, in page user space.
const _area = PdfRedactionArea(1, left: 100, bottom: 100, right: 200, top: 200);

/// Coordinates chosen so they appear nowhere else in a content stream, which
/// is what lets a test assert that the geometry itself is gone rather than
/// merely hidden.
const _insideCoordinates = '133.7 141.9';
const _outsideCoordinates = '311.3 422.7';

Future<Uint8List> _page(String content, {PdfDictionary? resources}) async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  if (resources != null) {
    page.pdfRepresentation().put(PdfName.resources, resources);
  }
  page.pdfRepresentation().put(PdfName.contents,
      PdfStream.withBytes(Uint8List.fromList(latin1.encode(content)), 0));
  await document.close();
  return output.takeBytes();
}

/// The page's content streams, decompressed and concatenated. Searching this
/// is the only honest proof that a redaction removed data instead of covering
/// it: an overlay hides ink, it does not delete coordinates.
Future<String> _contentOf(Uint8List bytes, [int number = 1]) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  try {
    return latin1
        .decode(await (await document.pageAt(number))!.contentPayload());
  } finally {
    await document.close();
  }
}

/// Every XObject stream of page 1, decompressed, so nested Form artwork can be
/// searched the same way.
Future<String> _xObjectsOf(Uint8List bytes) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  try {
    final page = (await document.pageAt(1))!;
    final resources =
        await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
    final xObjects = await resources?.dictionaryEntry(PdfName.xObject);
    if (xObjects == null) return '';
    final buffer = StringBuffer();
    for (final key in xObjects.keySet()) {
      final stream = await xObjects.streamEntry(key);
      final content = await stream?.getBytes();
      if (content != null) buffer.write(latin1.decode(content));
    }
    return buffer.toString();
  } finally {
    await document.close();
  }
}

/// The page's text, read back through the extractor.
Future<String> _textOf(Uint8List bytes) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(bytes));
  try {
    return await PdfTextExtraction.fromPage((await document.pageAt(1))!);
  } finally {
    await document.close();
  }
}

Future<Uint8List> _redact(Uint8List source,
        {PdfVectorArtRedaction vectorArt = PdfVectorArtRedaction.removeOrReject,
        bool overlay = false}) =>
    PdfAreaRedaction.apply(source, const [_area],
        options: PdfAreaRedactionOptions(
            paintOverlay: overlay, vectorArt: vectorArt));

void main() {
  group('vector artwork removal', () {
    test('a path inside the area leaves the content stream entirely', () async {
      final source = await _page('q 1 0 0 rg $_insideCoordinates 20 20 re f Q\n'
          'q 0 0 1 rg $_outsideCoordinates 50 50 re f Q\n');
      final content = await _contentOf(await _redact(source));
      expect(content, isNot(contains('133.7')));
      expect(content, isNot(contains('141.9')));
      expect(content, contains(_outsideCoordinates),
          reason: 'artwork outside the area must survive byte for byte');
      expect(content, contains('0 0 1 rg'));
    });

    test('removal is not an artefact of the overlay hiding the ink', () async {
      final source = await _page('$_insideCoordinates 20 20 re f\n');
      final content = await _contentOf(await _redact(source, overlay: true));
      expect(content, isNot(contains('133.7')));
      expect(content,
          matches(RegExp(r'100(\.0)? 100(\.0)? 100(\.0)? 100(\.0)? re')),
          reason: 'the overlay box is still drawn over the area');
    });

    test('a line, a curve and a closed subpath all go', () async {
      final source = await _page('110 110 m 150 150 l 170 130 l h f\n'
          '120 120 m 130 190.25 140 110 160 160 c S\n'
          '$_outsideCoordinates 10 10 re f\n');
      final content = await _contentOf(await _redact(source));
      for (final gone in ['110 110 m', '190.25', '170 130 l', '160 160 c']) {
        expect(content, isNot(contains(gone)), reason: gone);
      }
      expect(content, contains(_outsideCoordinates));
    });

    test('subpaths of one path object are judged one by one', () async {
      // The first subpath is inside the area and the second outside, so the
      // path object as a whole crosses the edge: it is rewritten with the
      // inside subpath gone and the outside one still there.
      final source = await _page(
          '110 110 m 150 150 l h $_outsideCoordinates m 350 450 l h f\n');
      final content = await _contentOf(await _redact(source));
      expect(content, isNot(contains('110 110')));
      expect(content, isNot(contains('150 150')));
      expect(content, contains('311.3 422.7 m'));
      expect(content, contains('350 450 l'));
    });

    test('the transformation matrix places the path, not the raw numbers',
        () async {
      // Both rectangles carry the same numbers; only the matrix decides which
      // of them lands in the area, and only that one goes.
      final source = await _page('q 1 0 0 1 120 130 cm 10.25 10.25 5 5 re f Q\n'
          'q 1 0 0 1 400 400 cm 10.25 10.25 5 5 re f Q\n');
      final content = await _contentOf(await _redact(source));
      expect('10.25 10.25 5 5 re'.allMatches(content).length, 1,
          reason: 'only the copy transformed into the area is removed');
      expect(content, contains('1 0 0 1 400 400 cm'));
    });
  });

  group('paths that cross an area edge', () {
    test('a stroke is refused, and the message says why', () async {
      // A stroke lays ink either side of its geometry, so clipping the
      // geometry against the area would leave part of the pen inside it.
      final source = await _page('90 90 40 40 re S\n');
      await expectLater(
          _redact(source),
          throwsA(isA<UnsupportedError>().having(
              (e) => e.message,
              'message',
              allOf(contains('crosses'), contains('pen width'),
                  contains('PdfVectorArtRedaction.cover')))));
    });

    test('a fill is clipped rather than refused or half-removed', () async {
      // A path that merely touches the area from outside is left alone, byte
      // for byte; one that reaches in is cut flush against the edge.
      final touching = await _page('0 0 100 100 re f\n');
      expect(await _contentOf(await _redact(touching)),
          contains('0 0 100 100 re'));

      final crossing = await _contentOf(
          await _redact(await _page('0 0 100.5 100.5 re f\n')));
      expect(crossing, isNot(contains('100.5 100.5')),
          reason: 'the corner that reached into the area is gone');
      expect(crossing, isNot(contains('re')),
          reason: 'the rectangle became an L cut flush against the edge');
      // What is left is the square minus its top right corner: everything
      // west of x=100 and, below y=100, the sliver east of it.
      expect(crossing, contains('100 100.5 l'));
      expect(crossing, contains('100.5 0 l'));
      expect(crossing, contains('f'));
    });

    test('cover keeps the cover-only behaviour on request', () async {
      final source = await _page('90 90 40 40 re f\n');
      final content = await _contentOf(
          await _redact(source, vectorArt: PdfVectorArtRedaction.cover));
      expect(content, contains('90 90 40 40 re'));
    });
  });

  group('stroke width', () {
    test('a stroke is judged by its ink, not by its geometry', () async {
      // Geometry from 150,150 to 160,160 sits well inside the area, so a
      // hairline pen is removable.
      final thin = await _page('0.5 w 150 150 m 160 160 l S\n');
      expect(
          await _contentOf(await _redact(thin)), isNot(contains('150 150 m')));

      // The same geometry with a 120-unit pen paints far outside the area.
      final fat = await _page('120 w 150 150 m 160 160 l S\n');
      await expectLater(_redact(fat), throwsUnsupportedError);
    });

    test('the pen is measured in the transformed space', () async {
      // A 1-unit pen under a 200x scale is a 200-unit pen on the page.
      final source =
          await _page('q 200 0 0 200 0 0 cm 1 w 0.75 0.75 m 0.8 0.8 l S Q\n');
      await expectLater(_redact(source), throwsUnsupportedError);
    });

    test('an unresolvable graphics state is not guessed at', () async {
      // /GS is not in the resources, so its pen width is unknown and the
      // stroke cannot be shown to stay inside the area.
      final source = await _page('/GS gs 150 150 m 160 160 l S\n');
      await expectLater(_redact(source), throwsUnsupportedError);

      final resources = PdfDictionary()
        ..put(
            PdfName('ExtGState'),
            PdfDictionary()
              ..put(
                  PdfName('GS'),
                  PdfDictionary()
                    ..put(PdfName('Type'), PdfName('ExtGState'))
                    ..put(PdfName('LW'), PdfNumber(0.5))));
      final declared =
          await _page('/GS gs 150 150 m 160 160 l S\n', resources: resources);
      expect(await _contentOf(await _redact(declared)),
          isNot(contains('150 150 m')));
    });

    test('a fill is not padded by the current pen width', () async {
      final source = await _page('120 w 150 150 20 20 re f\n');
      expect(
          await _contentOf(await _redact(source)), isNot(contains('150 150')));
    });
  });

  group('nested and neighbouring content', () {
    test('artwork inside a Form XObject is removed too', () async {
      final form = PdfStream.withBytes(
          Uint8List.fromList(latin1.encode('55.5 55.5 10 10 re f\n')), 0)
        ..put(PdfName.type, PdfName('XObject'))
        ..put(PdfName.subtype, PdfName('Form'))
        ..put(PdfName('BBox'), PdfArray.fromDoubles([0, 0, 100, 100]));
      final resources = PdfDictionary()
        ..put(PdfName.xObject, PdfDictionary()..put(PdfName('Art'), form));
      // The form is placed so its 55.5,55.5 rectangle lands at 155.5,155.5.
      final source =
          await _page('q 1 0 0 1 100 100 cm /Art Do Q\n', resources: resources);
      expect(await _xObjectsOf(source), contains('55.5 55.5'));
      final redacted = await _redact(source);
      expect(await _xObjectsOf(redacted), isNot(contains('55.5 55.5')));
      expect(await _contentOf(redacted), contains('/Art Do'));
    });

    test('a Form placed outside the area keeps its artwork', () async {
      final form = PdfStream.withBytes(
          Uint8List.fromList(latin1.encode('55.5 55.5 10 10 re f\n')), 0)
        ..put(PdfName.type, PdfName('XObject'))
        ..put(PdfName.subtype, PdfName('Form'))
        ..put(PdfName('BBox'), PdfArray.fromDoubles([0, 0, 100, 100]));
      final resources = PdfDictionary()
        ..put(PdfName.xObject, PdfDictionary()..put(PdfName('Art'), form));
      final source =
          await _page('q 1 0 0 1 400 400 cm /Art Do Q\n', resources: resources);
      expect(await _xObjectsOf(await _redact(source)), contains('55.5 55.5'));
    });

    test('artwork that crosses the edge inside a Form XObject is clipped too',
        () async {
      // The form is placed at 100,100, so its own 40..190 square lands at
      // 140..290 on the page and its lower left corner reaches into the area.
      // Mapped back into the form, the area is the 0..100 square.
      final form = PdfStream.withBytes(
          Uint8List.fromList(latin1.encode('40 40 150 150 re f\n')), 0)
        ..put(PdfName.type, PdfName('XObject'))
        ..put(PdfName.subtype, PdfName('Form'))
        ..put(PdfName('BBox'), PdfArray.fromDoubles([0, 0, 300, 300]));
      final resources = PdfDictionary()
        ..put(PdfName.xObject, PdfDictionary()..put(PdfName('Art'), form));
      final source =
          await _page('q 1 0 0 1 100 100 cm /Art Do Q\n', resources: resources);
      final art = await _xObjectsOf(await _redact(source));
      expect(art, isNot(contains('40 40 150 150 re')),
          reason: 'the rectangle was cut against the area mapped into the '
              "form's own space");
      // What is left is the square less its 40..100 corner: the slab east of
      // x=100 and, west of it, the part north of y=100.
      expect(art, contains('100 40 m'));
      expect(art, contains('190 190 l'));
      expect(art, contains('100 100 m'));
      expect(art, contains('40 100 l'));
    });

    test('a clipping path is preserved, and that is documented', () async {
      // Deleting a clip would widen what the rest of the page shows, so the
      // path stays even though it sits inside the area.
      final source =
          await _page('q $_insideCoordinates 20 20 re W n 0 0 1 rg Q\n');
      expect(await _contentOf(await _redact(source)), contains('133.7'));
    });

    test('inline image samples are not read as path operators', () async {
      // The nine sample bytes spell "110 110 f", a path object that would sit
      // inside the area; read as operators they would be deleted and the
      // image left corrupt.
      final source = await _page('q 1 0 0 1 300 300 cm '
          'BI /W 9 /H 1 /BPC 8 /CS /G ID 110 110 f EI Q\n'
          '$_insideCoordinates 20 20 re f\n');
      final content = await _contentOf(await _redact(source));
      expect(content, contains('ID 110 110 f EI'));
      expect(content, isNot(contains('133.7')));
    });

    test('text in the area is still removed alongside the artwork', () async {
      final font = PdfDictionary()
        ..put(PdfName.type, PdfName.font)
        ..put(PdfName.subtype, PdfName('Type1'))
        ..put(PdfName.baseFont, PdfName('Helvetica'))
        ..put(PdfName.encoding, PdfName('WinAnsiEncoding'));
      final resources = PdfDictionary()
        ..put(PdfName.font, PdfDictionary()..put(PdfName('F1'), font));
      final source = await _page(
          'BT /F1 12 Tf 110 150 Td (SECRET) Tj ET\n'
          '$_insideCoordinates 20 20 re f\n'
          'BT /F1 12 Tf 300 700 Td (PUBLIC) Tj ET\n',
          resources: resources);
      final redacted = await _redact(source);
      expect(await _contentOf(redacted), isNot(contains('133.7')),
          reason: 'the artwork under the area is gone from the stream');
      final text = await _textOf(redacted);
      expect(text, isNot(contains('SECRET')));
      expect(text, contains('PUBLIC'));
    });
  });
}
