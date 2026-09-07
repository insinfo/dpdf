import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/platform/compression.dart';
import 'package:test/test.dart';

/// Packed 1-bit rows in **PDF** polarity, where a set bit is white.
///
/// The page is mostly white with periodic black bars, the shape a scanned
/// text page has and the one JBIG2 is built for.
Uint8List _scannedPage({
  required int width,
  required int height,
  bool noisy = true,
}) {
  final stride = (width + 7) >> 3;
  final data = Uint8List(stride * height)..fillRange(0, stride * height, 0xff);
  final random = Random(7);
  for (var y = 0; y < height; y++) {
    final inLine = y % 40 >= 4 && y % 40 < 16;
    for (var x = 0; x < width; x++) {
      var black = false;
      if (inLine && x > 60 && x < width - 60) {
        black = (x ~/ 9) % 4 != 0;
        // Per-pixel jitter, so no two rows are identical. Without it the page
        // is perfectly periodic and deflate's literal matching wins, which is
        // exactly the case PdfBilevelCodec.auto exists to get right.
        if (noisy && random.nextInt(12) == 0) black = !black;
      } else if (noisy && random.nextInt(400) == 0) {
        black = true;
      }
      if (black) data[y * stride + (x >> 3)] &= ~(1 << (7 - (x & 7))) & 0xff;
    }
  }
  return data;
}

/// A document with one full-page bi-level image, stored with [filter].
Future<Uint8List> _scan({
  int width = 800,
  int height = 1000,
  PdfName? filter,
  bool noisy = true,
}) async {
  final samples = _scannedPage(width: width, height: height, noisy: noisy);
  final payload = filter?.getValue() == 'FlateDecode'
      ? Uint8List.fromList(ZLibEncoder(level: 9).convert(samples))
      : samples;

  final output = BytesBuilder(copy: false);
  final document = await PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  final image = buildBilevelImage(
    width: width,
    height: height,
    packedRows: payload,
    filter: filter,
  )..attachToDocument(document);
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

Future<Uint8List> _twoRepeatedScans() async {
  const width = 800, height = 1000;
  final samples = _scannedPage(width: width, height: height, noisy: false);
  final output = BytesBuilder(copy: false);
  final document = await PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  for (var index = 0; index < 2; index++) {
    final page = await document.appendBlankPage();
    final image = buildBilevelImage(
        width: width, height: height, packedRows: Uint8List.fromList(samples))
      ..attachToDocument(document);
    page.pdfRepresentation()
      ..put(
          PdfName.resources,
          PdfDictionary()
            ..put(PdfName.xObject,
                PdfDictionary()..put(PdfName('Im0'), image.indirectHandle()!)))
      ..put(
          PdfName.contents,
          PdfStream.withBytes(
              Uint8List.fromList(
                  ascii.encode('q 595 0 0 842 0 0 cm /Im0 Do Q')),
              0));
  }
  await document.close();
  return output.takeBytes();
}

/// Reads the image back and returns its decoded samples in PDF polarity.
Future<Uint8List> _samplesOf(Uint8List pdf) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(pdf));
  try {
    final page = (await document.pageAt(1))!;
    final resources =
        await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
    final xobjects = await resources!.dictionaryEntry(PdfName('XObject'));
    final image = await xobjects!.streamEntry(PdfName('Im0'));
    return (await image!.getBytes())!;
  } finally {
    await document.close();
  }
}

void main() {
  group('PdfImageCompressor through PdfCompressor', () {
    test('re-encodes an uncompressed scanned page as JBIG2', () async {
      final source = await _scan();

      final result = await PdfCompressor.compress(source);

      expect(result.report.images.imagesRecompressed, equals(1));
      expect(result.report.images.bytesSaved, greaterThan(0));
      expect(latin1.decode(result.bytes, allowInvalid: true),
          contains('/JBIG2Decode'));
      expect(result.report.compressedSize, lessThan(source.length ~/ 4),
          reason: result.report.toString());
    });

    test('symbol dictionaries beat deflate on the periodic text page',
        () async {
      // Com regiões genéricas, o Flate vencia esta página. A deduplicação de
      // símbolos repetidos torna JBIG2 menor e a seleção automática muda.
      final source = await _scan(noisy: false);

      final result = await PdfCompressor.compress(source);

      expect(result.report.images.imagesRecompressed, equals(1));
      expect(latin1.decode(result.bytes, allowInvalid: true),
          contains('/JBIG2Decode'));
    });

    test('shares one JBIG2Globals dictionary between repeated PDF images',
        () async {
      final source = await _twoRepeatedScans();
      final expected = _scannedPage(width: 800, height: 1000, noisy: false);
      final result = await PdfCompressor.compress(source,
          options: const PdfCompressionOptions(
              images:
                  PdfImageCompressionOptions(bilevel: PdfBilevelCodec.jbig2)));

      expect(result.report.images.imagesRecompressed, equals(2));
      final document =
          await PdfDocument.open(PdfReader.fromBytes(result.bytes));
      try {
        PdfObject? globals;
        for (var pageNumber = 1; pageNumber <= 2; pageNumber++) {
          final page = (await document.pageAt(pageNumber))!;
          final resources =
              await page.pdfRepresentation().dictionaryEntry(PdfName.resources);
          final objects = await resources!.dictionaryEntry(PdfName.xObject);
          final image = await objects!.streamEntry(PdfName('Im0'));
          expect(
              await image!.nameEntry(PdfName.filter), PdfName('JBIG2Decode'));
          final parms = await image.dictionaryEntry(PdfName('DecodeParms'));
          final current = await parms!.get(PdfName('JBIG2Globals'), false);
          expect(current, isNotNull);
          globals ??= current;
          expect(current, same(globals));
          expect(await image.getBytes(), expected);
        }
      } finally {
        await document.close();
      }
    });

    test('the re-encoded image decodes back to the same pixels', () async {
      final source = await _scan();
      final before = await _samplesOf(source);

      final result = await PdfCompressor.compress(source);
      final after = await _samplesOf(result.bytes);

      expect(after.length, equals(before.length));
      for (var i = 0; i < before.length; i++) {
        if (before[i] != after[i]) {
          fail('byte $i changed from ${before[i]} to ${after[i]}');
        }
      }
    });

    test('JBIG2 beats deflate on a page with scanner noise', () async {
      final source = await _scan();

      final withJbig2 = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions(bilevel: PdfBilevelCodec.jbig2),
        ),
      );
      final withFlate = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions(bilevel: PdfBilevelCodec.flate),
        ),
      );

      expect(withJbig2.bytes.length, lessThan(withFlate.bytes.length),
          reason: 'jbig2 ${withJbig2.bytes.length} vs '
              'flate ${withFlate.bytes.length}');
    });

    test('auto is never worse than either codec alone', () async {
      for (final noisy in [true, false]) {
        final source = await _scan(noisy: noisy);
        final auto = await PdfCompressor.compress(source);
        final jbig2 = await PdfCompressor.compress(
          source,
          options: const PdfCompressionOptions(
            images: PdfImageCompressionOptions(bilevel: PdfBilevelCodec.jbig2),
          ),
        );
        final flate = await PdfCompressor.compress(
          source,
          options: const PdfCompressionOptions(
            images: PdfImageCompressionOptions(bilevel: PdfBilevelCodec.flate),
          ),
        );

        expect(auto.bytes.length, lessThanOrEqualTo(jbig2.bytes.length),
            reason: 'noisy=$noisy auto vs jbig2');
        expect(auto.bytes.length, lessThanOrEqualTo(flate.bytes.length),
            reason: 'noisy=$noisy auto vs flate');
      }
    });

    test('improves on an already deflated image', () async {
      final source = await _scan(filter: PdfName('FlateDecode'));

      final result = await PdfCompressor.compress(source);

      expect(result.report.images.imagesRecompressed, equals(1));
      expect(result.bytes.length, lessThan(source.length));
    });

    test('leaves images alone when told to', () async {
      final source = await _scan();

      final result = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(
          images: PdfImageCompressionOptions.none,
        ),
      );

      expect(result.report.images.imagesRecompressed, isZero);
      expect(latin1.decode(result.bytes, allowInvalid: true),
          isNot(contains('/JBIG2Decode')));
    });

    test('skips an image too small to be worth re-encoding', () async {
      final source = await _scan(width: 32, height: 32);

      final result = await PdfCompressor.compress(source);

      expect(result.report.images.imagesRecompressed, isZero);
      expect(result.report.images.imagesSkipped, equals(1));
    });

    test('the conservative profile does not touch images', () async {
      final source = await _scan();

      final result = await PdfCompressor.compress(
        source,
        options: PdfCompressionOptions.conservative,
      );

      expect(result.report.images.imagesRecompressed, isZero);
    });

    test('reports the image pass in the machine readable map', () async {
      final source = await _scan();

      final json = (await PdfCompressor.compress(source)).report.toJson();

      expect(json['images'], isA<Map<Object?, Object?>>());
      expect((json['images']! as Map)['imagesRecompressed'], equals(1));
    });
  });
}
