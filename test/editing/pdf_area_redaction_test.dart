import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
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
