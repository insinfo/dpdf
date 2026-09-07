import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

CraftPdfDictionary _helvetica() => CraftPdfDictionary()
  ..put(CraftPdfName.type, CraftPdfName.font)
  ..put(CraftPdfName.subtype, CraftPdfName('Type1'))
  ..put(CraftPdfName.baseFont, CraftPdfName('Helvetica'))
  ..put(CraftPdfName.encoding, CraftPdfName('WinAnsiEncoding'));

/// A document with [pages] text pages, each carrying an uncompressed content
/// stream and its own copy of the same font dictionary — the shape a naive
/// generator produces and a compressor should be able to improve.
Future<Uint8List> _report(
    {int pages = 20, bool fullCompression = false}) async {
  final output = BytesBuilder(copy: false);
  final properties = CraftWriterProperties()
    ..setFullCompressionMode(fullCompression);
  final document = await CraftPdfDocument.create(
      CraftPdfWriter.fromBytesBuilder(output, properties: properties));

  for (var i = 1; i <= pages; i++) {
    final page = await document.appendBlankPage();
    // Each page gets its own indirect copy of the same font dictionary, the
    // way a generator that does not cache resources emits them. Only indirect
    // objects can be shared, so this is what deduplication has to merge.
    final font = _helvetica()..attachToDocument(document);
    page.pdfRepresentation().put(
        CraftPdfName.resources,
        CraftPdfDictionary()
          ..put(
              CraftPdfName.font,
              CraftPdfDictionary()
                ..put(CraftPdfName('F1'), font.indirectHandle()!)));
    final text = StringBuffer();
    for (var line = 0; line < 30; line++) {
      text.writeln('BT /F1 11 Tf 72 ${740 - line * 20} Td '
          '(Linha $line da pagina $i deste relatorio de exemplo) Tj ET');
    }
    page.pdfRepresentation().put(
        CraftPdfName.contents,
        CraftPdfStream.withBytes(
            Uint8List.fromList(latin1.encode(text.toString())), 0));
  }
  await document.close();
  return output.takeBytes();
}

Future<int> _pageCount(Uint8List bytes) async {
  final document = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
  try {
    return document.pageTotal();
  } finally {
    await document.close();
  }
}

Future<String> _textOf(Uint8List bytes, int page) async {
  final document = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
  try {
    return await PdfTextExtraction.fromPage((await document.pageAt(page))!);
  } finally {
    await document.close();
  }
}

void main() {
  group('PdfCompressor', () {
    test('makes an uncompressed document substantially smaller', () async {
      final source = await _report();

      final result = await PdfCompressor.compress(source);

      expect(result.report.compressedSize, lessThan(source.length));
      expect(result.report.ratio, greaterThan(0.5),
          reason: result.report.toString());
      expect(result.report.bytesSaved, greaterThan(0));
    });

    test('keeps every page readable and its text intact', () async {
      final source = await _report(pages: 5);

      final result = await PdfCompressor.compress(source);

      expect(await _pageCount(result.bytes), equals(5));
      final text = await _textOf(result.bytes, 3);
      expect(text, contains('Linha 0 da pagina 3'));
      expect(text, contains('Linha 29 da pagina 3'));
    });

    test('recompresses the content streams and says how much it saved',
        () async {
      final source = await _report(pages: 5);

      final result = await PdfCompressor.compress(source);

      expect(result.report.streamsRecompressed, greaterThan(0));
      expect(result.report.streamBytesSaved, greaterThan(0));
    });

    test('packs objects into object streams when asked', () async {
      final source = await _report(pages: 5);

      final packed = await PdfCompressor.compress(source);
      final loose = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(objectStreams: false),
      );

      final packedText = latin1.decode(packed.bytes, allowInvalid: true);
      final looseText = latin1.decode(loose.bytes, allowInvalid: true);
      expect(packedText, contains('/ObjStm'));
      expect(looseText, isNot(contains('/ObjStm')));
      expect(packed.bytes.length, lessThan(loose.bytes.length));
    });

    test('merges the identical font dictionary every page carries', () async {
      final source = await _report(pages: 10);

      final merged = await PdfCompressor.compress(source);
      final untouched = await PdfCompressor.compress(
        source,
        options: const PdfCompressionOptions(deduplicateObjects: false),
      );

      expect(merged.report.duplicatesMerged, greaterThan(0));
      expect(untouched.report.duplicatesMerged, isZero);
      expect(await _pageCount(merged.bytes), equals(10));
    });

    test('leaves an already compressed document alone rather than growing it',
        () async {
      final source = await _report(pages: 10, fullCompression: true);

      final first = await PdfCompressor.compress(source);
      final second = await PdfCompressor.compress(first.bytes);

      // Compressing twice must converge, not oscillate.
      expect(second.bytes.length,
          lessThanOrEqualTo((first.bytes.length * 1.02).ceil()),
          reason: '${first.bytes.length} then ${second.bytes.length}');
      expect(await _pageCount(second.bytes), equals(10));
    });

    test('removes thumbnails and private application data by default',
        () async {
      final output = BytesBuilder(copy: false);
      final document = await CraftPdfDocument.create(
          CraftPdfWriter.fromBytesBuilder(output));
      final page = await document.appendBlankPage();
      page.pdfRepresentation()
        ..put(CraftPdfName('Thumb'),
            CraftPdfStream.withBytes(Uint8List.fromList([1, 2, 3]), 0))
        ..put(
            CraftPdfName('PieceInfo'),
            CraftPdfDictionary()
              ..put(CraftPdfName('MyApp'), CraftPdfName('private')));
      await document.close();
      final source = output.takeBytes();

      final result = await PdfCompressor.compress(source);

      expect(result.report.entriesRemoved['Thumb'], equals(1));
      expect(result.report.entriesRemoved['PieceInfo'], equals(1));
      expect(latin1.decode(result.bytes, allowInvalid: true),
          isNot(contains('/PieceInfo')));
    });

    test('keeps metadata unless explicitly asked to remove it', () async {
      final output = BytesBuilder(copy: false);
      final document = await CraftPdfDocument.create(
          CraftPdfWriter.fromBytesBuilder(output));
      await document.appendBlankPage();
      await document.assignMetadataPayload(
          Uint8List.fromList(latin1.encode('<x:xmpmeta/>')));
      await document.close();
      final source = output.takeBytes();

      final kept = await PdfCompressor.compress(source);
      final dropped = await PdfCompressor.compress(
        source,
        options: PdfCompressionOptions.aggressive,
      );

      expect(kept.report.entriesRemoved.containsKey('Metadata'), isFalse);
      expect(dropped.report.entriesRemoved['Metadata'], greaterThan(0));
    });

    test('the conservative profile keeps thumbnails and piece info', () async {
      final source = await _report(pages: 3);

      final result = await PdfCompressor.compress(
        source,
        options: PdfCompressionOptions.conservative,
      );

      expect(result.report.entriesRemoved, isEmpty);
      expect(result.bytes.length, lessThan(source.length));
    });

    test('rejects a compression level outside the deflate range', () async {
      final source = await _report(pages: 1);

      expect(
        () => PdfCompressor.compress(source,
            options: const PdfCompressionOptions(compressionLevel: 12)),
        throwsArgumentError,
      );
    });

    test('reports its work in a machine readable map', () async {
      final source = await _report(pages: 3);

      final json = (await PdfCompressor.compress(source)).report.toJson();

      expect(json['originalSize'], equals(source.length));
      expect(json['compressedSize'], isA<int>());
      expect(json['ratio'], isA<double>());
      expect(json['entriesRemoved'], isA<Map<Object?, Object?>>());
    });
    test('returns the original when the rewrite would be larger', () async {
      // A tiny document costs more in cross-reference and object streams than
      // the structure saves, so the compressor must hand back what it got.
      final output = BytesBuilder(copy: false);
      final document = await CraftPdfDocument.create(
          CraftPdfWriter.fromBytesBuilder(output));
      await document.appendBlankPage();
      await document.close();
      final tiny = output.takeBytes();

      final kept = await PdfCompressor.compress(tiny);

      expect(kept.report.keptOriginal, isTrue);
      expect(kept.bytes.length, equals(tiny.length));
      expect(kept.report.bytesSaved, isZero);
      expect(kept.report.toString(), contains('kept'));
    });

    test('can be told to keep the rewrite even when it grew', () async {
      final output = BytesBuilder(copy: false);
      final document = await CraftPdfDocument.create(
          CraftPdfWriter.fromBytesBuilder(output));
      await document.appendBlankPage();
      await document.close();
      final tiny = output.takeBytes();

      final grown = await PdfCompressor.compress(
        tiny,
        options: const PdfCompressionOptions(neverGrow: false),
      );

      expect(grown.report.keptOriginal, isFalse);
      expect(await _pageCount(grown.bytes), equals(1));
    });
  });
}
