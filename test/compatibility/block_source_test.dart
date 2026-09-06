import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:pdfcraft/pdfcraft.dart';
import 'package:test/test.dart';

Uint8List largePdf() {
  final out = BytesBuilder();
  void add(String value) => out.add(ascii.encode(value));
  add('%PDF-1.7\n');
  final offsets = <int>[0];
  void object(int number, String value) {
    offsets.add(out.length);
    add('$number 0 obj\n$value\nendobj\n');
  }

  object(1, '<< /Type /Catalog /Pages 2 0 R >>');
  object(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  object(3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>');
  offsets.add(out.length);
  const length = 4 * 1024 * 1024;
  add('4 0 obj\n<< /Length $length >>\nstream\n');
  out.add(Uint8List(length));
  add('\nendstream\nendobj\n');
  final xref = out.length;
  add('xref\n0 5\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    add('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  add('trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return out.takeBytes();
}

void main() {
  late Directory temp;
  setUp(
      () => temp = Directory.systemTemp.createTempSync('pdfcraft-block-test-'));
  tearDown(() => temp.deleteSync(recursive: true));
  test('file cache crosses blocks, evicts, and preserves independent cursors',
      () {
    final bytes = Uint8List.fromList(List.generate(10000, (i) => i % 251));
    final file = File('${temp.path}/input.bin')..writeAsBytesSync(bytes);
    final source = PdfFileSource.open(file.path, blockSize: 1024, maxBlocks: 2);
    final input = CraftRandomAccessFileOrArray.fromSource(source);
    final view = input.createView();
    input.seek(1015);
    final actual = Uint8List(3200);
    input.readFully(actual);
    expect(actual, bytes.sublist(1015, 4215));
    expect(source.cachedBytes, lessThanOrEqualTo(2048));
    expect(view.read(), bytes.first);
    view.close();
    expect(input.read(), bytes[4215]);
    input.close();
    expect(() => source.byteAt(0), throwsStateError);
  });
  test('opening PDF reads only header/xref/page blocks and closes the file',
      () async {
    final file = File('${temp.path}/large.pdf')..writeAsBytesSync(largePdf());
    final source = PdfFileSource.open(file.path, blockSize: 4096, maxBlocks: 4);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromSource(source));
    expect(doc.pageTotal(), 1);
    expect(source.bytesRead, lessThan(100000));
    expect(source.cachedBytes, lessThanOrEqualTo(16384));
    await doc.close();
    expect(() => source.byteAt(0), throwsStateError);
  });
  test(
      'file reader flag and recovery skip large streams through the block cache',
      () async {
    final damaged = Uint8List.fromList(latin1.encode(latin1
        .decode(largePdf())
        .replaceFirst(RegExp(r'startxref\s+\d+'), 'startxref\n99999999')));
    final file = File('${temp.path}/damaged.pdf')..writeAsBytesSync(damaged);
    final source = PdfFileSource.open(file.path, blockSize: 4096, maxBlocks: 4);
    final doc = await CraftPdfDocument.open(CraftPdfReader.fromSource(source,
        CraftReaderProperties()..recoveryMode = PdfRecoveryMode.skipStreams));
    expect(doc.pageTotal(), 1);
    expect(doc.wasRepaired, isTrue);
    expect(source.bytesRead, lessThan(150000));
    await doc.close();
    final properties = CraftReaderProperties()
      ..readFileInBlocks = true
      ..fileBlockSize = 4096
      ..fileCacheBlocks = 4
      ..recoveryMode = PdfRecoveryMode.skipStreams;
    final reader = await CraftPdfReader.fromFile(file.path, properties);
    final reopened = await CraftPdfDocument.open(reader);
    expect(reopened.wasRepaired, isTrue);
    expect(reopened.pageTotal(), 1);
    await reopened.close();
  });
  test(
      'incremental file-backed save copies original chunks and preserves prefix',
      () async {
    final bytes = largePdf();
    final file = File('${temp.path}/large.pdf')..writeAsBytesSync(bytes);
    final source = PdfFileSource.open(file.path, blockSize: 4096, maxBlocks: 4);
    final output = BytesBuilder();
    final doc = CraftPdfDocument(
        reader: CraftPdfReader.fromSource(source),
        writer: CraftPdfWriter.fromBytesBuilder(output),
        properties: CraftStampingProperties()..useAppendMode());
    await doc.load();
    (await doc.pageAt(1))!.setRotationDegrees(90);
    await doc.close();
    final result = output.takeBytes();
    expect(result.sublist(0, bytes.length), bytes);
    final reopened =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(result));
    expect(
        await (await reopened.pageAt(1))!
            .pdfRepresentation()
            .get(CraftPdfName.rotate),
        (isA<CraftPdfNumber>()));
    await reopened.close();
  });
}
