import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/io/image/jpeg_decoder.dart';
import 'package:test/test.dart';

/// A smooth colour field, which is what JPEG is good at and what a raw
/// 8-bit-per-channel image stores wastefully.
Uint8List _photo(int width, int height) {
  final pixels = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      pixels[i] = (x * 255 ~/ (width - 1));
      pixels[i + 1] = (y * 255 ~/ (height - 1));
      pixels[i + 2] = 128 + ((x - y) * 60 ~/ (width + height));
    }
  }
  return pixels;
}

/// A document whose single page carries one 8-bit RGB image, stored raw.
Future<Uint8List> _document({
  int width = 240,
  int height = 180,
  Uint8List? pixels,
  int channels = 3,
  double displayWidth = 595,
  double displayHeight = 842,
  bool paintTwiceLarger = false,
  bool insideScaledForm = false,
}) async {
  final samples = pixels ?? _photo(width, height);
  final output = BytesBuilder(copy: false);
  final document = await PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();

  final image = PdfStream.withBytes(samples, 0)
    ..put(PdfName.type, PdfName('XObject'))
    ..put(PdfName.subtype, PdfName('Image'))
    ..put(PdfName.width, PdfNumber.fromInt(width))
    ..put(PdfName.height, PdfNumber.fromInt(height))
    ..put(PdfName('BitsPerComponent'), PdfNumber.fromInt(8))
    ..put(PdfName('ColorSpace'),
        PdfName(channels == 1 ? 'DeviceGray' : 'DeviceRGB'));
  image.attachToDocument(document);

  if (insideScaledForm) {
    final form = PdfStream.withBytes(
        Uint8List.fromList(ascii
            .encode('q $displayWidth 0 0 $displayHeight 0 0 cm /Im0 Do Q')),
        0)
      ..put(PdfName.type, PdfName('XObject'))
      ..put(PdfName.subtype, PdfName('Form'))
      ..put(PdfName('BBox'), PdfArray.fromDoubles([0, 0, 100, 100]))
      ..put(PdfName('Matrix'), PdfArray.fromDoubles([2, 0, 0, 2, 0, 0]))
      ..put(
          PdfName.resources,
          PdfDictionary()
            ..put(PdfName.xObject,
                PdfDictionary()..put(PdfName('Im0'), image.indirectHandle()!)));
    form.attachToDocument(document);
    page.pdfRepresentation()
      ..put(
          PdfName.resources,
          PdfDictionary()
            ..put(PdfName.xObject,
                PdfDictionary()..put(PdfName('Fm0'), form.indirectHandle()!)))
      ..put(PdfName.contents,
          PdfStream.withBytes(Uint8List.fromList(ascii.encode('/Fm0 Do')), 0));
  } else {
    page.pdfRepresentation().put(
        PdfName.resources,
        PdfDictionary()
          ..put(PdfName.xObject,
              PdfDictionary()..put(PdfName('Im0'), image.indirectHandle()!)));
    page.pdfRepresentation().put(
        PdfName.contents,
        PdfStream.withBytes(
            Uint8List.fromList(ascii.encode(
                'q $displayWidth 0 0 $displayHeight 0 0 cm /Im0 Do Q '
                '${paintTwiceLarger ? 'q ${displayWidth * 2} 0 0 ${displayHeight * 2} 0 0 cm /Im0 Do Q' : ''}')),
            0));
  }
  await document.close();
  return output.takeBytes();
}

/// The image XObject on page 1, so a test can read back what was written.
Future<PdfStream> _imageOf(Uint8List pdf) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(pdf));
  final page = (await document.pageAt(1))!;
  final resources =
      await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
  final xobjects = await resources!.dictionaryEntry(PdfName('XObject'));
  return (await xobjects!.streamEntry(PdfName('Im0')))!;
}

void main() {
  group('continuous-tone images', () {
    test('are left alone by default', () async {
      final source = await _document();

      final result = await PdfCompressor.compress(source);

      expect(result.report.images.imagesRecompressed, isZero);
      expect(latin1.decode(result.bytes, allowInvalid: true),
          isNot(contains('/DCTDecode')));
    });

    test('become JPEG when the lossy profile asks for it', () async {
      final source = await _document();

      final result = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions.lossy(quality: 75),
        ),
      );

      expect(result.report.images.imagesRecompressed, equals(1));
      expect(result.report.images.bytesSaved, greaterThan(0));
      expect(latin1.decode(result.bytes, allowInvalid: true),
          contains('/DCTDecode'));
      expect(result.bytes.length, lessThan(source.length ~/ 3),
          reason: result.report.toString());
    });

    test('keep their dimensions and stay decodable', () async {
      final source = await _document();

      final result = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions.lossy(quality: 90),
        ),
      );

      final image = await _imageOf(result.bytes);
      expect(await image.integerEntry(PdfName.width), equals(240));
      expect(await image.integerEntry(PdfName.height), equals(180));

      final decoded = JpegDecoder.decode((await image.getRawBytes())!);
      expect(decoded.width, equals(240));
      expect(decoded.height, equals(180));
      expect(decoded.format, equals(JpegPixelFormat.rgb));
    });

    test('are downsampled to the cap and the dictionary follows', () async {
      final source = await _document(width: 400, height: 300);

      final result = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions.lossy(maxDimension: 100),
        ),
      );

      final image = await _imageOf(result.bytes);
      expect(await image.integerEntry(PdfName.width), equals(100));
      expect(await image.integerEntry(PdfName.height), equals(75));

      final decoded = JpegDecoder.decode((await image.getRawBytes())!);
      expect(decoded.width, equals(100));
      expect(decoded.height, equals(75));
    });

    test('are downsampled from their effective page DPI', () async {
      final source = await _document(
          width: 400, height: 300, displayWidth: 72, displayHeight: 54);

      final result = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions.lossy(targetDpi: 100),
        ),
      );

      final image = await _imageOf(result.bytes);
      expect(await image.integerEntry(PdfName.width), equals(100));
      expect(await image.integerEntry(PdfName.height), equals(75));
    });

    test('a reused image keeps the pixels needed by its largest use', () async {
      final source = await _document(
          width: 400,
          height: 300,
          displayWidth: 72,
          displayHeight: 54,
          paintTwiceLarger: true);

      final result = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions.lossy(targetDpi: 100),
        ),
      );

      final image = await _imageOf(result.bytes);
      expect(await image.integerEntry(PdfName.width), equals(200));
      expect(await image.integerEntry(PdfName.height), equals(150));
    });

    test('effective DPI follows image placement inside a transformed form',
        () async {
      final source = await _document(
          width: 400,
          height: 300,
          displayWidth: 36,
          displayHeight: 27,
          insideScaledForm: true);

      final result = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions.lossy(targetDpi: 100),
        ),
      );

      final document =
          await PdfDocument.open(PdfReader.fromBytes(result.bytes));
      try {
        final page = (await document.pageAt(1))!;
        final resources =
            await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
        final forms = await resources!.dictionaryEntry(PdfName.xObject);
        final form = await forms!.streamEntry(PdfName('Fm0'));
        final formResources = await form!.dictionaryEntry(PdfName.resources);
        final images = await formResources!.dictionaryEntry(PdfName.xObject);
        final image = await images!.streamEntry(PdfName('Im0'));
        expect(await image!.integerEntry(PdfName.width), equals(100));
        expect(await image.integerEntry(PdfName.height), equals(75));
      } finally {
        await document.close();
      }
    });

    test('rejects a non-positive target DPI', () async {
      final source = await _document();
      expect(
          () => PdfCompressor.compress(
                source,
                options: const PdfCompressionOptions(
                  images: PdfImageCompressionOptions.lossy(targetDpi: 0),
                ),
              ),
          throwsArgumentError);
    });

    test('a lower quality yields a smaller document', () async {
      final source = await _document();

      final high = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions.lossy(quality: 95),
        ),
      );
      final low = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions.lossy(quality: 40),
        ),
      );

      expect(low.bytes.length, lessThan(high.bytes.length));
    });

    test('grayscale stays grayscale', () async {
      const width = 200, height = 150;
      final gray = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          gray[y * width + x] = (x + y) & 0xff;
        }
      }
      final source = await _document(
          width: width, height: height, pixels: gray, channels: 1);

      final result = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions.lossy(quality: 85),
        ),
      );

      final image = await _imageOf(result.bytes);
      expect((await image.nameEntry(PdfName('ColorSpace')))?.getValue(),
          equals('DeviceGray'));
      final decoded = JpegDecoder.decode((await image.getRawBytes())!);
      expect(decoded.format, equals(JpegPixelFormat.grayscale));
    });

    test('an image already smaller than the cap is not resized', () async {
      final source = await _document(width: 240, height: 180);

      final result = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions.lossy(maxDimension: 1000),
        ),
      );

      final image = await _imageOf(result.bytes);
      expect(await image.integerEntry(PdfName.width), equals(240));
      expect(await image.integerEntry(PdfName.height), equals(180));
    });

    test('recompressing an existing JPEG keeps it readable', () async {
      final source = await _document();

      final once = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions.lossy(quality: 90),
        ),
      );
      // The second pass now sees a DCTDecode stream, so it exercises the
      // decode-existing-JPEG branch rather than the raw-samples one.
      final twice = await PdfCompressor.compress(
        once.bytes,
        options: const PdfCompressionOptions(
          images:
              PdfImageCompressionOptions.lossy(quality: 50, maxDimension: 120),
        ),
      );

      final image = await _imageOf(twice.bytes);
      expect(await image.integerEntry(PdfName.width), equals(120));
      final decoded = JpegDecoder.decode((await image.getRawBytes())!);
      expect(decoded.width, equals(120));
      expect(decoded.height, equals(90));
    });
  });
}
