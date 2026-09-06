import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pdfcraft/src/editing/pdf_text_extraction.dart';
import 'package:pdfcraft/src/editing/pdf_encoding_differences.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_array.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_dictionary.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_name.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_number.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_object.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_reader.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_stream.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_writer.dart';

Future<String> extract(List<CraftPdfObject> entries, String hex,
    {String? base, bool unicode = false, String fontName = 'Helvetica'}) async {
  final output = BytesBuilder();
  final document =
      await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  final encoding = CraftPdfDictionary()
    ..put(CraftPdfName('Differences'), CraftPdfArray.fromList(entries));
  if (base != null)
    encoding.put(CraftPdfName('BaseEncoding'), CraftPdfName(base));
  final font = CraftPdfDictionary()
    ..put(CraftPdfName.subtype, CraftPdfName('Type1'))
    ..put(CraftPdfName.baseFont, CraftPdfName(fontName))
    ..put(CraftPdfName.encoding, encoding);
  if (unicode) {
    font.put(
        CraftPdfName('ToUnicode'),
        CraftPdfStream.withBytes(
            Uint8List.fromList(ascii.encode(
                'begincmap 1 begincodespacerange <00> <FF> endcodespacerange '
                '1 beginbfchar <41> <005A> endbfchar endcmap')),
            0));
  }
  page.pdfRepresentation().put(
      CraftPdfName.resources,
      CraftPdfDictionary()
        ..put(CraftPdfName.font,
            CraftPdfDictionary()..put(CraftPdfName('F1'), font)));
  page.pdfRepresentation().put(
      CraftPdfName.contents,
      CraftPdfStream.withBytes(
          Uint8List.fromList(ascii.encode('BT /F1 12 Tf <$hex> Tj ET')), 0));
  await document.close();
  final reopened =
      await CraftPdfDocument.open(CraftPdfReader.fromBytes(output.takeBytes()));
  try {
    return await PdfTextExtraction.fromPage((await reopened.pageAt(1))!);
  } finally {
    await reopened.close();
  }
}

void main() {
  test('Dictionary values have explicit types', () async {
    await expectLater(
        PdfEncodingDifferences.parse(CraftPdfDictionary()
          ..put(CraftPdfName('BaseEncoding'), CraftPdfNumber(1))),
        throwsFormatException);
    await expectLater(
        PdfEncodingDifferences.parse(CraftPdfDictionary()
          ..put(CraftPdfName('Differences'), CraftPdfName('A'))),
        throwsFormatException);
    await expectLater(
        PdfEncodingDifferences.parse(CraftPdfDictionary()
          ..put(CraftPdfName('BaseEncoding'), CraftPdfName('Unknown'))),
        throwsUnsupportedError);
  });
  test('Differences override Base14 quotes and preserve base characters',
      () async {
    expect(
        await extract(
            [CraftPdfNumber(39), CraftPdfName('quotesingle')], '274160'),
        "'A‘");
  });
  test('Portuguese names, reset index and WinAnsi fallback', () async {
    expect(
        await extract([
          CraftPdfNumber(1),
          CraftPdfName('ccedilla'),
          CraftPdfName('atilde'),
          CraftPdfNumber(5),
          CraftPdfName('Euro')
        ], '6101026F0527', base: 'WinAnsiEncoding'),
        "ação€'");
  });
  test('AGL suffixes, sequences and supplementary scalars', () async {
    expect(
        await extract([
          CraftPdfNumber(1),
          CraftPdfName('uni00660069.alt'),
          CraftPdfName('u1F600'),
          CraftPdfName('A_uni0301'),
          CraftPdfName('dalethatafpatah')
        ], '01020304'),
        'fi😀A\u0301\u05d3\u05b2');
  });
  test('Unknown glyph rejected only on use, including partially known name',
      () async {
    expect(
        await extract([CraftPdfNumber(1), CraftPdfName('unknown')], '41'), 'A');
    for (final name in [
      'unknown',
      '.notdef',
      'A_unknown',
      'uniD800',
      'u110000',
      'uni20ac'
    ]) {
      await expectLater(extract([CraftPdfNumber(1), CraftPdfName(name)], '01'),
          throwsUnsupportedError);
    }
  });
  test('Malformed differences fail without rounding or overflow', () async {
    for (final entries in <List<CraftPdfObject>>[
      [CraftPdfName('A')],
      [CraftPdfNumber(-1)],
      [CraftPdfNumber(256)],
      [CraftPdfNumber(1.5)],
      [CraftPdfNumber(255), CraftPdfName('A'), CraftPdfName('B')],
      [CraftPdfNumber(1), CraftPdfArray()]
    ]) {
      await expectLater(extract(entries, '41'), throwsFormatException);
    }
  });
  test('ToUnicode takes precedence even over malformed Differences', () async {
    expect(await extract([CraftPdfName('invalid')], '41', unicode: true), 'Z');
  });
  test('Unknown built-in font requires mapping only for unmapped codes',
      () async {
    expect(
        await extract([CraftPdfNumber(65), CraftPdfName('A')], '41',
            fontName: 'Custom'),
        'A');
    await expectLater(
        extract([CraftPdfNumber(65), CraftPdfName('A')], '42',
            fontName: 'Custom'),
        throwsUnsupportedError);
  });
}
