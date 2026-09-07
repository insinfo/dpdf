import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/render/image_decoder.dart';
import 'package:test/test.dart';

/// One page with three lines of Helvetica, each on its own baseline, so a
/// rectangle can single out a line without touching its neighbours.
Future<Uint8List> _threeLines() async {
  final output = BytesBuilder(copy: false);
  final document = await PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  final font = PdfDictionary()
    ..put(PdfName.type, PdfName.font)
    ..put(PdfName.subtype, PdfName('Type1'))
    ..put(PdfName.baseFont, PdfName('Helvetica'))
    ..put(PdfName.encoding, PdfName('WinAnsiEncoding'));
  page.pdfRepresentation().put(
      PdfName.resources,
      PdfDictionary()
        ..put(PdfName.font, PdfDictionary()..put(PdfName('F1'), font)));

  const content = 'BT /F1 12 Tf 72 700 Td (PUBLIC HEADING) Tj ET\n'
      'BT /F1 12 Tf 72 660 Td (SECRET ACCOUNT 12345) Tj ET\n'
      'BT /F1 12 Tf 72 620 Td (PUBLIC FOOTER) Tj ET\n';
  page.pdfRepresentation().put(PdfName.contents,
      PdfStream.withBytes(Uint8List.fromList(ascii.encode(content)), 0));
  await document.close();
  return output.takeBytes();
}

Future<String> _textOf(Uint8List bytes, [int page = 1]) async {
  final reader = PdfReader.fromBytes(bytes);
  final document = await PdfDocument.open(reader);
  try {
    return await PdfTextExtraction.fromPage((await document.pageAt(page))!);
  } finally {
    await document.close();
  }
}

Future<Uint8List> _imagePage({bool transparent = false, int pages = 1}) async {
  const width = 10, height = 10;
  final pixels = Uint8List(width * height * 3);
  for (var i = 0; i < width * height; i++) {
    pixels[i * 3] = 240;
    pixels[i * 3 + 1] = 30;
    pixels[i * 3 + 2] = 180;
  }
  final output = BytesBuilder(copy: false);
  final document = await PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final image = PdfStream.withBytes(pixels, 0)
    ..put(PdfName.type, PdfName('XObject'))
    ..put(PdfName.subtype, PdfName('Image'))
    ..put(PdfName.width, PdfNumber.fromInt(width))
    ..put(PdfName.height, PdfNumber.fromInt(height))
    ..put(PdfName('BitsPerComponent'), PdfNumber.fromInt(8))
    ..put(PdfName('ColorSpace'), PdfName('DeviceRGB'));
  if (transparent) {
    final mask = PdfStream.withBytes(
        Uint8List(width * height)..fillRange(0, width * height, 64), 0)
      ..put(PdfName.type, PdfName('XObject'))
      ..put(PdfName.subtype, PdfName('Image'))
      ..put(PdfName.width, PdfNumber.fromInt(width))
      ..put(PdfName.height, PdfNumber.fromInt(height))
      ..put(PdfName('BitsPerComponent'), PdfNumber.fromInt(8))
      ..put(PdfName('ColorSpace'), PdfName('DeviceGray'));
    mask.attachToDocument(document);
    image.put(PdfName('SMask'), mask.indirectHandle()!);
  }
  image.attachToDocument(document);
  for (var index = 0; index < pages; index++) {
    final page = await document.appendBlankPage();
    page.pdfRepresentation()
      ..put(
          PdfName.resources,
          PdfDictionary()
            ..put(PdfName.xObject,
                PdfDictionary()..put(PdfName('Scan'), image.indirectHandle()!)))
      ..put(
          PdfName.contents,
          PdfStream.withBytes(
              Uint8List.fromList(
                  ascii.encode('q 100 0 0 100 50 50 cm /Scan Do Q')),
              0));
  }
  await document.close();
  return output.takeBytes();
}

Future<Uint8List> _formImagePage() async {
  const width = 10, height = 10;
  final pixels = Uint8List(width * height * 3);
  for (var i = 0; i < width * height; i++) {
    pixels.setRange(i * 3, i * 3 + 3, const [240, 30, 180]);
  }
  final output = BytesBuilder(copy: false);
  final document = await PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final image = PdfStream.withBytes(pixels, 0)
    ..put(PdfName.type, PdfName('XObject'))
    ..put(PdfName.subtype, PdfName('Image'))
    ..put(PdfName.width, PdfNumber.fromInt(width))
    ..put(PdfName.height, PdfNumber.fromInt(height))
    ..put(PdfName('BitsPerComponent'), PdfNumber.fromInt(8))
    ..put(PdfName('ColorSpace'), PdfName('DeviceRGB'));
  image.attachToDocument(document);
  final form = PdfStream.withBytes(
      Uint8List.fromList(ascii.encode('/Scan Do')), 0)
    ..put(PdfName.type, PdfName('XObject'))
    ..put(PdfName.subtype, PdfName('Form'))
    ..put(PdfName.bBox, PdfArray.fromDoubles(const [0, 0, 1, 1]))
    ..put(PdfName.matrix, PdfArray.fromDoubles(const [100, 0, 0, 100, 50, 50]))
    ..put(
        PdfName.resources,
        PdfDictionary()
          ..put(PdfName.xObject,
              PdfDictionary()..put(PdfName('Scan'), image.indirectHandle()!)));
  form.attachToDocument(document);
  final page = await document.appendBlankPage();
  page.pdfRepresentation()
    ..put(
        PdfName.resources,
        PdfDictionary()
          ..put(PdfName.xObject,
              PdfDictionary()..put(PdfName('Panel'), form.indirectHandle()!)))
    ..put(PdfName.contents,
        PdfStream.withBytes(Uint8List.fromList(ascii.encode('/Panel Do')), 0));
  await document.close();
  return output.takeBytes();
}

void main() {
  group('PdfAreaRedaction', () {
    test('removes only the characters inside the rectangle', () async {
      final source = await _threeLines();
      expect(await _textOf(source), contains('SECRET ACCOUNT 12345'));

      final redacted = await PdfAreaRedaction.apply(source, [
        PdfRedactionArea(1, left: 60, bottom: 655, right: 300, top: 675),
      ]);

      final text = await _textOf(redacted);
      expect(text, isNot(contains('SECRET')));
      expect(text, isNot(contains('12345')));
      expect(text, contains('PUBLIC HEADING'));
      expect(text, contains('PUBLIC FOOTER'));
    });

    test('leaves the page untouched when nothing falls in the area', () async {
      final source = await _threeLines();

      final redacted = await PdfAreaRedaction.apply(source, [
        PdfRedactionArea(1, left: 400, bottom: 100, right: 500, top: 200),
      ]);

      final text = await _textOf(redacted);
      expect(text, contains('PUBLIC HEADING'));
      expect(text, contains('SECRET ACCOUNT 12345'));
      expect(text, contains('PUBLIC FOOTER'));
    });

    test('cuts a rectangle that covers part of one line', () async {
      final source = await _threeLines();

      // "SECRET " is seven glyphs of 12pt Helvetica starting at x=72; the
      // rectangle stops well before the account number.
      final redacted = await PdfAreaRedaction.apply(source, [
        PdfRedactionArea(1, left: 70, bottom: 655, right: 120, top: 675),
      ]);

      final text = await _textOf(redacted);
      expect(text, isNot(contains('SECRET')));
      expect(text, contains('12345'));
    });

    test('paints an overlay by default and can be told not to', () async {
      final source = await _threeLines();
      const area =
          PdfRedactionArea(1, left: 60, bottom: 655, right: 300, top: 675);

      final withBox = await PdfAreaRedaction.apply(source, [area]);
      final withoutBox = await PdfAreaRedaction.apply(
        source,
        [area],
        options: const PdfAreaRedactionOptions(paintOverlay: false),
      );

      expect(latin1.decode(withBox, allowInvalid: true), contains(' re'));
      expect(withoutBox.length, lessThan(withBox.length));
      expect(await _textOf(withoutBox), isNot(contains('SECRET')));
    });

    test('removes source pixels from an opaque scanned image', () async {
      final source = await _imagePage();
      final redacted = await PdfAreaRedaction.apply(
        source,
        const [PdfRedactionArea(1, left: 50, bottom: 50, right: 100, top: 150)],
        options: const PdfAreaRedactionOptions(paintOverlay: false),
      );

      final document = await PdfDocument.open(PdfReader.fromBytes(redacted));
      try {
        final page = (await document.pageAt(1))!;
        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final xobjects = await resources!.dictionaryEntry(PdfName.xObject);
        final image = await xobjects!.streamEntry(PdfName('Scan'));
        final decoded = await PdfImageDecoder.decode(image!);
        expect(decoded, isNotNull);
        for (var y = 0; y < 10; y++) {
          for (var x = 0; x < 10; x++) {
            final at = (y * 10 + x) * 4;
            if (x < 5) {
              expect(decoded!.rgba!.sublist(at, at + 3), equals([0, 0, 0]));
            } else {
              expect(
                  decoded!.rgba!.sublist(at, at + 3), equals([240, 30, 180]));
            }
          }
        }
      } finally {
        await document.close();
      }
    });

    test('removes source pixels from an image nested in a Form XObject',
        () async {
      final redacted = await PdfAreaRedaction.apply(
        await _formImagePage(),
        const [PdfRedactionArea(1, left: 50, bottom: 50, right: 100, top: 150)],
        options: const PdfAreaRedactionOptions(paintOverlay: false),
      );
      final document = await PdfDocument.open(PdfReader.fromBytes(redacted));
      try {
        final page = (await document.pageAt(1))!;
        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final pageObjects = await resources!.dictionaryEntry(PdfName.xObject);
        final form = await pageObjects!.streamEntry(PdfName('Panel'));
        final formResources = await form!.dictionaryEntry(PdfName.resources);
        final formObjects =
            await formResources!.dictionaryEntry(PdfName.xObject);
        final image = await formObjects!.streamEntry(PdfName('Scan'));
        final decoded = await PdfImageDecoder.decode(image!);
        for (var y = 0; y < 10; y++) {
          for (var x = 0; x < 10; x++) {
            final rgb =
                decoded!.rgba!.sublist((y * 10 + x) * 4, (y * 10 + x) * 4 + 3);
            expect(rgb, x < 5 ? equals([0, 0, 0]) : equals([240, 30, 180]));
          }
        }
      } finally {
        await document.close();
      }
    });

    test('rewrites transparent image pixels and preserves alpha outside',
        () async {
      final source = await _imagePage(transparent: true);
      final redacted = await PdfAreaRedaction.apply(
        source,
        const [PdfRedactionArea(1, left: 50, bottom: 50, right: 100, top: 150)],
        options: const PdfAreaRedactionOptions(paintOverlay: false),
      );

      final document = await PdfDocument.open(PdfReader.fromBytes(redacted));
      try {
        final page = (await document.pageAt(1))!;
        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final xobjects = await resources!.dictionaryEntry(PdfName.xObject);
        final image = await xobjects!.streamEntry(PdfName('Scan'));
        final decoded = await PdfImageDecoder.decode(image!);
        expect(decoded, isNotNull);
        for (var y = 0; y < 10; y++) {
          for (var x = 0; x < 10; x++) {
            final at = (y * 10 + x) * 4;
            if (x < 5) {
              expect(
                  decoded!.rgba!.sublist(at, at + 4), equals([0, 0, 0, 255]));
            } else {
              expect(decoded!.rgba!.sublist(at, at + 4),
                  equals([240, 30, 180, 64]));
            }
          }
        }
      } finally {
        await document.close();
      }
    });

    test('clones a shared image instead of changing an unredacted page',
        () async {
      final source = await _imagePage(pages: 2);
      final redacted = await PdfAreaRedaction.apply(
        source,
        const [PdfRedactionArea(1, left: 50, bottom: 50, right: 100, top: 150)],
        options: const PdfAreaRedactionOptions(paintOverlay: false),
      );

      final document = await PdfDocument.open(PdfReader.fromBytes(redacted));
      try {
        Future<PdfDecodedImage> imageOn(int number) async {
          final page = (await document.pageAt(number))!;
          final resources =
              await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
          final xobjects = await resources!.dictionaryEntry(PdfName.xObject);
          return (await PdfImageDecoder.decode(
              (await xobjects!.streamEntry(PdfName('Scan')))!))!;
        }

        final first = await imageOn(1);
        final second = await imageOn(2);
        expect(first.rgba!.sublist(0, 3), [0, 0, 0]);
        expect(second.rgba!.sublist(0, 3), [240, 30, 180]);
      } finally {
        await document.close();
      }
    });

    test('rejects an empty or non-finite area', () async {
      final source = await _threeLines();

      expect(
        () => PdfAreaRedaction.apply(source, const []),
        throwsArgumentError,
      );
      expect(
        () => PdfAreaRedaction.apply(source, [
          const PdfRedactionArea(1, left: 100, bottom: 100, right: 50, top: 90),
        ]),
        throwsArgumentError,
      );
      expect(
        () => PdfAreaRedaction.apply(source, [
          const PdfRedactionArea(1,
              left: double.nan, bottom: 0, right: 10, top: 10),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects a page number outside the document', () async {
      final source = await _threeLines();

      expect(
        () => PdfAreaRedaction.apply(source, [
          const PdfRedactionArea(9, left: 0, bottom: 0, right: 10, top: 10),
        ]),
        throwsRangeError,
      );
    });

    test('builds an area from a position and a size', () {
      final area =
          PdfRedactionArea.fromSize(1, x: 10, y: 20, width: 100, height: 50);

      expect(area.left, equals(10));
      expect(area.bottom, equals(20));
      expect(area.right, equals(110));
      expect(area.top, equals(70));
      expect(area.isEmpty, isFalse);
    });

    test('clears the document information dictionary when asked', () async {
      final source = await _threeLines();

      final redacted = await PdfAreaRedaction.apply(
        source,
        [
          const PdfRedactionArea(1, left: 60, bottom: 655, right: 300, top: 675)
        ],
        options: const PdfAreaRedactionOptions(clearDocumentInfo: true),
      );

      final reader = PdfReader.fromBytes(redacted);
      final document = await PdfDocument.open(reader);
      try {
        final info = await document.fileTrailer().dictionaryEntry(PdfName.info);
        expect(info == null || info.size() == 0, isTrue);
      } finally {
        await document.close();
      }
    });
  });
}
