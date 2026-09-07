import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/editing/pdf_encoding_differences.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';

Future<String> extract(List<PdfObject> entries, String hex,
    {String? base, bool unicode = false, String fontName = 'Helvetica'}) async {
  final output = BytesBuilder();
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  final encoding = PdfDictionary()
    ..put(PdfName('Differences'), PdfArray.fromList(entries));
  if (base != null) {
    encoding.put(PdfName('BaseEncoding'), PdfName(base));
  }
  final font = PdfDictionary()
    ..put(PdfName.subtype, PdfName('Type1'))
    ..put(PdfName.baseFont, PdfName(fontName))
    ..put(PdfName.encoding, encoding);
  if (unicode) {
    font.put(
        PdfName('ToUnicode'),
        PdfStream.withBytes(
            Uint8List.fromList(ascii.encode(
                'begincmap 1 begincodespacerange <00> <FF> endcodespacerange '
                '1 beginbfchar <41> <005A> endbfchar endcmap')),
            0));
  }
  page.pdfRepresentation().put(
      PdfName.resources,
      PdfDictionary()
        ..put(PdfName.font, PdfDictionary()..put(PdfName('F1'), font)));
  page.pdfRepresentation().put(
      PdfName.contents,
      PdfStream.withBytes(
          Uint8List.fromList(ascii.encode('BT /F1 12 Tf <$hex> Tj ET')), 0));
  await document.close();
  final reopened =
      await PdfDocument.open(PdfReader.fromBytes(output.takeBytes()));
  try {
    return await PdfTextExtraction.fromPage((await reopened.pageAt(1))!);
  } finally {
    await reopened.close();
  }
}

void main() {
  test('Dictionary values have explicit types', () async {
    await expectLater(
        PdfEncodingDifferences.parse(
            PdfDictionary()..put(PdfName('BaseEncoding'), PdfNumber(1))),
        throwsFormatException);
    await expectLater(
        PdfEncodingDifferences.parse(
            PdfDictionary()..put(PdfName('Differences'), PdfName('A'))),
        throwsFormatException);
    await expectLater(
        PdfEncodingDifferences.parse(
            PdfDictionary()..put(PdfName('BaseEncoding'), PdfName('Unknown'))),
        throwsUnsupportedError);
  });
  test('Differences override Base14 quotes and preserve base characters',
      () async {
    expect(await extract([PdfNumber(39), PdfName('quotesingle')], '274160'),
        "'A‘");
  });
  test('Portuguese names, reset index and WinAnsi fallback', () async {
    expect(
        await extract([
          PdfNumber(1),
          PdfName('ccedilla'),
          PdfName('atilde'),
          PdfNumber(5),
          PdfName('Euro')
        ], '6101026F0527', base: 'WinAnsiEncoding'),
        "ação€'");
  });
  test('AGL suffixes, sequences and supplementary scalars', () async {
    expect(
        await extract([
          PdfNumber(1),
          PdfName('uni00660069.alt'),
          PdfName('u1F600'),
          PdfName('A_uni0301'),
          PdfName('dalethatafpatah')
        ], '01020304'),
        'fi😀A\u0301\u05d3\u05b2');
  });
  test('Unknown glyph rejected only on use, including partially known name',
      () async {
    expect(await extract([PdfNumber(1), PdfName('unknown')], '41'), 'A');
    for (final name in [
      'unknown',
      '.notdef',
      'A_unknown',
      'uniD800',
      'u110000',
      'uni20ac'
    ]) {
      await expectLater(
          extract([PdfNumber(1), PdfName(name)], '01'), throwsUnsupportedError);
    }
  });
  test('Malformed differences fail without rounding or overflow', () async {
    for (final entries in <List<PdfObject>>[
      [PdfName('A')],
      [PdfNumber(-1)],
      [PdfNumber(256)],
      [PdfNumber(1.5)],
      [PdfNumber(255), PdfName('A'), PdfName('B')],
      [PdfNumber(1), PdfArray()]
    ]) {
      await expectLater(extract(entries, '41'), throwsFormatException);
    }
  });
  test('ToUnicode takes precedence even over malformed Differences', () async {
    expect(await extract([PdfName('invalid')], '41', unicode: true), 'Z');
  });
  test('Unknown built-in font requires mapping only for unmapped codes',
      () async {
    expect(
        await extract([PdfNumber(65), PdfName('A')], '41', fontName: 'Custom'),
        'A');
    await expectLater(
        extract([PdfNumber(65), PdfName('A')], '42', fontName: 'Custom'),
        throwsUnsupportedError);
  });
}
