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

  page.pdfRepresentation().put(
      PdfName.resources,
      PdfDictionary()
        ..put(PdfName('XObject'),
            PdfDictionary()..put(PdfName('Im0'), image.indirectHandle()!)));
  page.pdfRepresentation().put(
      PdfName.contents,
      PdfStream.withBytes(
          Uint8List.fromList(ascii.encode('q 595 0 0 842 0 0 cm /Im0 Do Q')),
          0));
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
