import 'dart:convert';
import 'dart:typed_data';
import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/writer_properties.dart';

Uint8List bytes(String text) => Uint8List.fromList(latin1.encode(text));
String source({String suffix = '', String extras = '', int generation = 0}) =>
    '%PDF-1.7\n1 $generation obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
    '2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n$extras'
    'trailer\n<< /Root 1 $generation R /Size 3 >>\n$suffix';
PdfReader reader(String text, PdfRecoveryMode mode) =>
    PdfReader.fromBytes(bytes(text), ReaderProperties()..recoveryMode = mode);

void main() {
  for (final mode in [PdfRecoveryMode.scan, PdfRecoveryMode.skipStreams]) {
    for (final suffix in [
      '',
      'startxref\n99999999\n%%EOF\n',
      'startxref\n1\n%%EOF\n'
    ]) {
      test('$mode rebuilds missing or broken startxref: $suffix', () async {
        final input = reader(source(suffix: suffix), mode);
        final doc = await PdfDocument.open(input);
        expect(input.rebuiltXref, isTrue);
        expect(doc.pageTotal(), 0);
        await doc.close();
      });
    }
    test('$mode finds catalog without trailer', () async {
      final input = reader(source().split('trailer').first, mode);
      await input.read();
      expect(await input.rootCatalog(), isNotNull);
      expect(input.rebuiltXref, isTrue);
      input.close();
    });
    test('$mode keeps latest definition and generation', () async {
      final input = reader(
          source(
                  extras:
                      '1 1 obj\n<< /Type /Catalog /Pages 2 0 R /Version /Latest >>\nendobj\n')
              .replaceAll('/Root 1 0 R', '/Root 1 1 R'),
          mode);
      await input.read();
      expect(input.xref.get(1)!.generationNumber(), 1);
      expect(
          (await (await input.rootCatalog())!.nameEntry(PdfName.version))!
              .getValue(),
          'Latest');
      input.close();
    });
    for (final length in ['', '/Length 99999', '/Length 9 0 R', '/Length 51']) {
      test('$mode ignores fake object headers in streams, $length', () async {
        final payload =
            '1 9 obj\n<< /Type /Catalog /Version /Fake >>\nendobj\n';
        final input = reader(
            source(
                extras:
                    '3 0 obj\n<< $length >>\nstream\n${payload}endstream\nendobj\n'),
            mode);
        await input.read();
        expect(input.xref.get(1)!.generationNumber(), 0);
        expect(await (await input.rootCatalog())!.nameEntry(PdfName.version),
            isNull);
        input.close();
      });
    }
  }
  test(
      'skipStreams verifies the real length before skipping delimiter-like payload',
      () async {
    final payload =
        'a\nendstream\nendobj\n1 9 obj\n<< /Type /Catalog >>\nendobj\n';
    final input = reader(
        source(
            extras:
                '3 0 obj\n<< /Length ${payload.length} >>\nstream\n${payload}endstream\nendobj\n'),
        PdfRecoveryMode.skipStreams);
    await input.read();
    expect(input.xref.get(1)!.generationNumber(), 0);
    expect(input.rebuiltXref, isTrue);
    input.close();
  });
  for (final length in ['', '/Length -1', '/Length 99999', '/Length 9 0 R']) {
    test('Repaired stream $length can be read and rewritten', () async {
      final text = source(
              extras:
                  '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R >>\nendobj\n'
                  '4 0 obj\n<< $length >>\nstream\nq 1 0 0 1 0 0 cm Q\nendstream\nendobj\n')
          .replaceFirst('/Kids [] /Count 0', '/Kids [3 0 R] /Count 1');
      final input = reader(text, PdfRecoveryMode.skipStreams);
      await input.read();
      final content = await input.readObject(4) as PdfStream;
      expect(
          latin1.decode((await content.getBytes())!), 'q 1 0 0 1 0 0 cm Q\n');
      input.close();
      final output = BytesBuilder();
      final document = PdfDocument(
          reader: reader(text, PdfRecoveryMode.skipStreams),
          writer: PdfWriter.fromBytesBuilder(output));
      await document.load();
      await document.close();
      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
      expect(reopened.pageTotal(), 1);
      final page = (await reopened.pageAt(1))!;
      final stream = await page.pdfRepresentation().get(PdfName.contents, true)
          as PdfStream;
      expect(latin1.decode((await stream.getBytes())!), 'q 1 0 0 1 0 0 cm Q\n');
      await reopened.close();
    });
  }
  for (final mode in [PdfRecoveryMode.scan, PdfRecoveryMode.skipStreams]) {
    test('$mode recovers generated object streams, text and full rewrite',
        () async {
      final buffer = BytesBuilder();
      final original = PdfDocument.create(PdfWriter.fromBytesBuilder(buffer,
          properties: WriterProperties().setFullCompressionMode(true)));
      final page = await original.appendBlankPage();
      final overlay = await PdfPageOverlay.create(page);
      overlay.beginText();
      await overlay.setFontAndSize(PdfFontFactory.createFont('Helvetica'), 12);
      overlay.moveText(20, 30).showText('RECOVERED OBJECT STREAM').endText();
      await original.close();
      final encoded = latin1.decode(buffer.takeBytes());
      expect(encoded, contains('/ObjStm'));
      final damaged =
          encoded.replaceFirst(RegExp(r'startxref\s+\d+'), 'startxref\n1');
      final input = reader(damaged, mode);
      final document = await PdfDocument.open(input);
      expect(input.rebuiltXref, isTrue);
      expect(document.pageTotal(), 1);
      expect(await PdfTextExtraction.fromPage((await document.pageAt(1))!),
          contains('RECOVERED OBJECT STREAM'));
      await document.close();
      final output = BytesBuilder();
      final rewrite = PdfDocument(
          reader: reader(damaged, mode),
          writer: PdfWriter.fromBytesBuilder(output));
      await rewrite.load();
      await rewrite.close();
      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
      expect(await PdfTextExtraction.fromPage((await reopened.pageAt(1))!),
          contains('RECOVERED OBJECT STREAM'));
      await reopened.close();
    });
  }
  test('Recovery rejects encrypted trailers before object stream decoding',
      () async {
    final input = reader(
        source().replaceFirst('/Size 3', '/Size 3 /Encrypt 8 0 R'),
        PdfRecoveryMode.scan);
    await expectLater(input.read(), throwsUnsupportedError);
    expect(input.rebuiltXref, isFalse);
    input.close();
  });
  test('Recovery rejects out-of-bounds object stream offsets', () async {
    final payload = '4 999 << /Type /Catalog >>';
    final input = reader(
        source(
            extras:
                '3 0 obj\n<< /Type /ObjStm /N 1 /First 6 /Length ${payload.length} >>\nstream\n$payload\nendstream\nendobj\n'),
        PdfRecoveryMode.skipStreams);
    await expectLater(input.read(), throwsFormatException);
    expect(input.rebuiltXref, isFalse);
    input.close();
  });
  test('Strict remains the default and rejects a missing xref', () async {
    expect(ReaderProperties().recoveryMode, PdfRecoveryMode.strict);
    await expectLater(PdfDocument.open(PdfReader.fromBytes(bytes(source()))),
        throwsException);
  });
  test('Recovery enforces input and object limits', () async {
    for (final properties in [
      ReaderProperties()..recoveryScanLimit = 10,
      ReaderProperties()..recoveryObjectLimit = 1
    ]) {
      properties.recoveryMode = PdfRecoveryMode.scan;
      final input = PdfReader.fromBytes(bytes(source()), properties);
      await expectLater(input.read(), throwsFormatException);
      expect(input.rebuiltXref, isFalse);
      input.close();
    }
  });
  test('Unterminated stream cannot produce a successful repair', () async {
    final input = reader(source(extras: '3 0 obj\n<< >>\nstream\nunterminated'),
        PdfRecoveryMode.scan);
    await expectLater(input.read(), throwsFormatException);
    expect(input.rebuiltXref, isFalse);
    input.close();
  });
}
