import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dpdf/dpdf.dart';
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

class SparseDamagedPdfSource implements PdfByteSource {
  static const streamLength = 3 * 1024 * 1024 * 1024;
  late final Uint8List prefix;
  late final Uint8List suffix;
  late final int suffixOffset;
  @override
  late final int length;
  int bytesRead = 0;

  SparseDamagedPdfSource() {
    prefix = Uint8List.fromList(ascii.encode('%PDF-1.7\n'
        '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
        '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
        '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>\nendobj\n'
        '4 0 obj\n<< /Length $streamLength /Subtype /Image '
        '/Width 1 /Height 1 /BitsPerComponent 1 >>\nstream\n'));
    suffix = Uint8List.fromList(ascii.encode('\nendstream\nendobj\n'
        'trailer\n<< /Size 5 /Root 1 0 R >>\n'
        'startxref\n9999999999\n%%EOF\n'));
    suffixOffset = prefix.length + streamLength;
    length = suffixOffset + suffix.length;
  }

  @override
  int byteAt(int offset) {
    if (offset < 0 || offset >= length) return -1;
    bytesRead++;
    if (offset < prefix.length) return prefix[offset];
    if (offset >= suffixOffset) return suffix[offset - suffixOffset];
    return 0;
  }

  @override
  int readInto(int position, Uint8List target, int offset, int count) {
    if (position >= length) return -1;
    final amount = count.clamp(0, length - position);
    target.fillRange(offset, offset + amount, 0);
    for (var i = 0; i < amount; i++) {
      final absolute = position + i;
      if (absolute < prefix.length) {
        target[offset + i] = prefix[absolute];
      } else if (absolute >= suffixOffset) {
        target[offset + i] = suffix[absolute - suffixOffset];
      }
    }
    bytesRead += amount;
    return amount;
  }

  @override
  void close() {}
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('dpdf-block-test-'));
  tearDown(() => temp.deleteSync(recursive: true));
  test('file cache crosses blocks, evicts, and preserves independent cursors',
      () {
    final bytes = Uint8List.fromList(List.generate(10000, (i) => i % 251));
    final file = File('${temp.path}/input.bin')..writeAsBytesSync(bytes);
    final source = PdfFileSource.open(file.path, blockSize: 1024, maxBlocks: 2);
    final input = RandomAccessFileOrArray.fromSource(source);
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
    final doc = await PdfDocument.open(PdfReader.fromSource(source));
    expect(doc.pageTotal(), 1);
    expect(source.bytesRead, lessThan(100000));
    expect(source.cachedBytes, lessThanOrEqualTo(16384));
    await doc.close();
    expect(() => source.byteAt(0), throwsStateError);
  });
  test('fromFile automatically uses blocks above the configured threshold',
      () async {
    final file = File('${temp.path}/automatic.pdf')
      ..writeAsBytesSync(largePdf());
    final properties = ReaderProperties()
      ..largeFileBlockThreshold = 1024
      ..fileBlockSize = 4096
      ..fileCacheBlocks = 4;
    final reader = await PdfReader.fromFile(file.path, properties);
    expect(reader.readsFileInBlocks, isTrue);
    final document = await PdfDocument.open(reader);
    expect(document.pageTotal(), 1);
    await document.close();
  });

  test('reader properties copy large-file and recovery limits', () {
    final original = ReaderProperties()
      ..largeFileBlockThreshold = 1234
      ..recoveryScanLimit = 5 * 1024 * 1024 * 1024;
    final copy = ReaderProperties.from(original);
    expect(copy.largeFileBlockThreshold, 1234);
    expect(copy.recoveryScanLimit, 5 * 1024 * 1024 * 1024);
  });
  test(
      'file reader flag and recovery skip large streams through the block cache',
      () async {
    final damaged = Uint8List.fromList(latin1.encode(latin1
        .decode(largePdf())
        .replaceFirst(RegExp(r'startxref\s+\d+'), 'startxref\n99999999')));
    final file = File('${temp.path}/damaged.pdf')..writeAsBytesSync(damaged);
    final source = PdfFileSource.open(file.path, blockSize: 4096, maxBlocks: 4);
    final doc = await PdfDocument.open(PdfReader.fromSource(source,
        ReaderProperties()..recoveryMode = PdfRecoveryMode.skipStreams));
    expect(doc.pageTotal(), 1);
    expect(doc.wasRepaired, isTrue);
    expect(source.bytesRead, lessThan(150000));
    await doc.close();
    final properties = ReaderProperties()
      ..readFileInBlocks = true
      ..fileBlockSize = 4096
      ..fileCacheBlocks = 4
      ..recoveryMode = PdfRecoveryMode.skipStreams;
    final reader = await PdfReader.fromFile(file.path, properties);
    final reopened = await PdfDocument.open(reader);
    expect(reopened.wasRepaired, isTrue);
    expect(reopened.pageTotal(), 1);
    await reopened.close();
  });
  test('repairs a sparse corrupted PDF larger than 3 GiB without reading it',
      () async {
    final source = SparseDamagedPdfSource();
    expect(source.length, greaterThan(3 * 1024 * 1024 * 1024));
    final watch = Stopwatch()..start();
    final document = await PdfDocument.open(PdfReader.fromSource(source,
        ReaderProperties()..recoveryMode = PdfRecoveryMode.skipStreams));
    watch.stop();

    expect(document.wasRepaired, isTrue);
    expect(document.pageTotal(), 1);
    final inventory = await PdfImageInventory.inspect(document);
    expect(inventory.images, hasLength(1));
    expect(inventory.images.single.objectNumber, 4);
    expect(inventory.images.single.encodedLength,
        SparseDamagedPdfSource.streamLength);
    expect(inventory.images.single.width, 1);
    expect(inventory.images.single.height, 1);
    expect(source.bytesRead, lessThan(2 * 1024 * 1024),
        reason: 'abrir e listar não deve ler o payload de 3 GiB');
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    await document.close();
  });
  test(
      'incremental file-backed save copies original chunks and preserves prefix',
      () async {
    final bytes = largePdf();
    final file = File('${temp.path}/large.pdf')..writeAsBytesSync(bytes);
    final source = PdfFileSource.open(file.path, blockSize: 4096, maxBlocks: 4);
    final output = BytesBuilder();
    final doc = PdfDocument(
        reader: PdfReader.fromSource(source),
        writer: PdfWriter.fromBytesBuilder(output),
        properties: StampingProperties()..useAppendMode());
    await doc.load();
    (await doc.pageAt(1))!.setRotationDegrees(90);
    await doc.close();
    final result = output.takeBytes();
    expect(result.sublist(0, bytes.length), bytes);
    final reopened = await PdfDocument.open(PdfReader.fromBytes(result));
    expect(
        await (await reopened.pageAt(1))!
            .pdfRepresentation()
            .get(PdfName.rotate),
        (isA<PdfNumber>()));
    await reopened.close();
  });
}
