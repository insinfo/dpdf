import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// ISO 32000-2, 7.5.2 allows arbitrary bytes before `%PDF-`: byte offsets are
/// counted from the PERCENT SIGN, so such a file stays perfectly viable.
///
/// The fixture is the PDF Association's own example of that provision; the
/// generated cases prove the same for a file this package produced itself.
void main() {
  group('a PDF whose header is not at byte 0', () {
    late Uint8List plain;

    setUpAll(() async => plain = await _sourceDocument());

    test('the official example opens, reads and extracts text', () async {
      final bytes =
          File('test/assets/pdf20-offset-start.pdf').readAsBytesSync();
      expect(bytes.length, 5264);
      expect(_headerAt(bytes), 656,
          reason: 'the fixture is the one with 656 bytes of commentary');

      final reader = PdfReader.fromBytes(bytes);
      expect(reader.headerOffset, 656);
      final document = await PdfDocument.open(reader);
      addTearDown(() async => document.close());

      expect(document.pageTotal(), 1);
      expect(reader.pdfVersion, '2.0');
      expect(reader.rebuiltXref, isFalse,
          reason: 'the declared xref must be usable as it stands');

      final page = await document.pageAt(1);
      final text = await PdfTextExtraction.fromPage(page!);
      expect(text.trim(), 'This is a PDF 2.0 document');
    });

    test('the official example raises no serious integrity finding', () async {
      final bytes =
          File('test/assets/pdf20-offset-start.pdf').readAsBytesSync();
      final report = await PdfIntegrityChecker.inspect(bytes);

      expect(report.readable, isTrue);
      expect(report.recoveryUsed, isFalse);
      expect(report.reachablePageCount, 1);
      expect(report.headerVersion, '2.0');
      expect(
        report.findings
            .where((f) => f.severity != PdfIntegritySeverity.info)
            .map((f) => f.code),
        isEmpty,
        reason: report.findings.join('\n'),
      );
      expect(
          report.findings.map((f) => f.code), contains('header-not-at-start'));
    });

    for (final junk in [1, 9, 656, 1023]) {
      test('$junk prefixed bytes read exactly like the original', () async {
        final shifted = _prefix(plain, junk);

        final reader = PdfReader.fromBytes(shifted);
        expect(reader.headerOffset, junk);
        final document = await PdfDocument.open(reader);
        addTearDown(() async => document.close());

        expect(document.pageTotal(), 3);
        expect(reader.pdfVersion, isNotNull);
        expect(reader.rebuiltXref, isFalse);
        expect(await _allText(document), await _referenceText(plain));
      });
    }

    test('reads the same through a block backed file source', () async {
      final shifted = _prefix(plain, 656);
      final directory = Directory.systemTemp.createTempSync('dpdf-offset');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}/shifted.pdf';
      File(path).writeAsBytesSync(shifted);

      // Blocks smaller than the junk prefix, so every read crosses the window.
      final reader = PdfReader.fromSource(
          PdfFileSource.open(path, blockSize: 256, maxBlocks: 2));
      expect(reader.headerOffset, 656);
      expect(reader.readsFileInBlocks, isTrue);
      final document = await PdfDocument.open(reader);
      addTearDown(() async => document.close());

      expect(document.pageTotal(), 3);
      expect(await _allText(document), await _referenceText(plain));
    });

    test('reads the same through PdfReader.fromFile in block mode', () async {
      final directory = Directory.systemTemp.createTempSync('dpdf-offset');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}/shifted.pdf';
      File(path).writeAsBytesSync(_prefix(plain, 9));

      final reader = await PdfReader.fromFile(
          path, ReaderProperties()..readFileInBlocks = true);
      expect(reader.headerOffset, 9);
      final document = await PdfDocument.open(reader);
      addTearDown(() async => document.close());
      expect(document.pageTotal(), 3);
    });

    test('drops the prefix when the document is rewritten', () async {
      final shifted = _prefix(plain, 656);
      final output = BytesBuilder();
      final document = PdfDocument(
          reader: PdfReader.fromBytes(shifted),
          writer: PdfWriter.fromBytesBuilder(output));
      await document.load();
      await document.close();

      final saved = output.takeBytes();
      expect(_headerAt(saved), 0,
          reason: 'the junk prefix is not part of the PDF data');
      final reopened = await PdfDocument.open(PdfReader.fromBytes(saved));
      addTearDown(() async => reopened.close());
      expect(reopened.pageTotal(), 3);
    });

    test('an incremental update keeps the file readable', () async {
      final shifted = _prefix(plain, 656);
      final output = BytesBuilder();
      final document = PdfDocument(
          reader: PdfReader.fromBytes(shifted),
          writer: PdfWriter.fromBytesBuilder(output),
          properties: StampingProperties()..useAppendMode());
      await document.load();
      await document.appendBlankPage();
      await document.close();

      final saved = output.takeBytes();
      expect(_headerAt(saved), 0,
          reason: 'the revision is appended to the PDF data, not to the junk');
      final reopened = await PdfDocument.open(PdfReader.fromBytes(saved));
      addTearDown(() async => reopened.close());
      expect(reopened.pageTotal(), 4);
    });

    test('recovery by scanning still finds the objects', () async {
      final shifted = _prefix(plain, 656);
      // Wreck the startxref pointer so the reader has to scan for objects.
      final broken = Uint8List.fromList(shifted);
      final marker = 'startxref'.codeUnits;
      final at = _lastIndexOf(broken, marker);
      expect(at, greaterThan(0));
      for (var index = at + marker.length + 1;
          index < broken.length &&
              broken[index] >= 0x30 &&
              broken[index] <= 0x39;
          index++) {
        broken[index] = 0x39;
      }

      final reader = PdfReader.fromBytes(
          broken, ReaderProperties()..recoveryMode = PdfRecoveryMode.scan);
      expect(reader.headerOffset, 656);
      final document = await PdfDocument.open(reader);
      addTearDown(() async => document.close());
      expect(reader.rebuiltXref, isTrue);
      expect(document.pageTotal(), 3);
    });
  });

  group('a header that is not there', () {
    test('a header past byte 1023 is refused', () async {
      final plain = await _sourceDocument();
      expect(
        () => PdfDocument.open(PdfReader.fromBytes(_prefix(plain, 1024))),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message',
            contains('no recognizable PDF header'))),
      );
    });

    test('a file with no header at all is refused', () async {
      final junk = Uint8List.fromList(
          List<int>.generate(4096, (index) => 0x41 + (index % 26)));
      expect(
        () => PdfDocument.open(PdfReader.fromBytes(junk)),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message',
            contains('no recognizable PDF header'))),
      );
    });
  });

  group('a PDF whose header is at byte 0', () {
    test('opens unchanged, with no window applied', () async {
      final plain = await _sourceDocument();
      final reader = PdfReader.fromBytes(plain);
      expect(reader.headerOffset, 0);
      final document = await PdfDocument.open(reader);
      addTearDown(() async => document.close());
      expect(document.pageTotal(), 3);
      expect(reader.readsFileInBlocks, isFalse,
          reason: 'the memory fast path must survive the change');
      expect(reader.getOriginalBytes(), same(plain));
    });

    test('the shipped fixture still opens', () async {
      final bytes = File('test/assets/test.pdf').readAsBytesSync();
      final reader = PdfReader.fromBytes(bytes);
      expect(reader.headerOffset, 0);
      final document = await PdfDocument.open(reader);
      addTearDown(() async => document.close());
      expect(document.pageTotal(), greaterThan(0));
    });
  });
}

int _headerAt(Uint8List bytes) {
  final window = bytes.length < 4096 ? bytes.length : 4096;
  return String.fromCharCodes(bytes.sublist(0, window)).indexOf('%PDF-');
}

int _lastIndexOf(Uint8List bytes, List<int> marker) {
  for (var index = bytes.length - marker.length; index >= 0; index--) {
    var matched = 0;
    while (
        matched < marker.length && bytes[index + matched] == marker[matched]) {
      matched++;
    }
    if (matched == marker.length) return index;
  }
  return -1;
}

Uint8List _prefix(Uint8List bytes, int junk) {
  final shifted = Uint8List(junk + bytes.length);
  for (var index = 0; index < junk; index++) {
    // Printable filler that contains no PDF marker of its own.
    shifted[index] = index % 40 == 39 ? 0x0A : 0x61 + (index % 26);
  }
  shifted.setRange(junk, shifted.length, bytes);
  return shifted;
}

Future<String> _allText(PdfDocument document) async {
  final parts = <String>[];
  for (var number = 1; number <= document.pageTotal(); number++) {
    final page = await document.pageAt(number);
    parts.add((await PdfTextExtraction.fromPage(page!)).trim());
  }
  return parts.join('\n');
}

Future<String> _referenceText(Uint8List plain) async {
  final document = await PdfDocument.open(PdfReader.fromBytes(plain));
  try {
    return await _allText(document);
  } finally {
    await document.close();
  }
}

/// A three page document produced by this package, used as the control.
Future<Uint8List> _sourceDocument() async {
  final output = BytesBuilder();
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final font = PdfFontFactory.createFont('Helvetica');
  for (var number = 1; number <= 3; number++) {
    final canvas = await PdfCanvas.fromPage(await document.appendBlankPage());
    canvas.beginText();
    await canvas.setFontAndSize(font, 18);
    canvas.moveText(40, 700).showText('Page $number').endText();
  }
  await document.close();
  return output.takeBytes();
}
