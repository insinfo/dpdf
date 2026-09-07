import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';

const cmapText = """/CIDInit /ProcSet findresource begin
12 dict begin begincmap
/CMapName /Fixture def /CMapType 2 def
1 begincodespacerange <0000> <FFFF> endcodespacerange
4 beginbfchar
<0001> <00E7> <0002> <4E2D> <0003> <D83DDE00> <0004> <00660069>
endbfchar
endcmap CMapName currentdict /CMap defineresource pop end end""";

Future<String> extract(
    {String? cmap = cmapText,
    String? encoding,
    String content = 'BT /F1 12 Tf <0001000200030004> Tj ET',
    bool compressed = false,
    bool inherited = false}) async {
  final output = BytesBuilder();
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  final font = PdfDictionary()
    ..put(PdfName.subtype, PdfName(cmap == null ? 'Type1' : 'Type0'))
    ..put(PdfName.baseFont, PdfName('Helvetica'));
  if (encoding != null) font.put(PdfName.encoding, PdfName(encoding));
  if (cmap != null) {
    final bytes = ascii.encode(cmap);
    final stream = PdfStream.withBytes(
        Uint8List.fromList(compressed ? zlib.encode(bytes) : bytes), 0);
    if (compressed) {
      stream.put(PdfName.filter, PdfName('FlateDecode'));
    }
    if (inherited) {
      stream.put(PdfName('UseCMap'), PdfName('Unsupported'));
    }
    font.put(PdfName('ToUnicode'), stream);
  }
  page.pdfRepresentation().put(
      PdfName.resources,
      PdfDictionary()
        ..put(PdfName.font, PdfDictionary()..put(PdfName('F1'), font)));
  page.pdfRepresentation().put(PdfName.contents,
      PdfStream.withBytes(Uint8List.fromList(ascii.encode(content)), 0));
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
  test('Malformed Contents fails instead of reporting empty text', () async {
    final document =
        PdfDocument.create(PdfWriter.fromBytesBuilder(BytesBuilder()));
    final page = await document.appendBlankPage();
    page.pdfRepresentation().put(PdfName.contents, PdfName('invalid'));
    await expectLater(PdfTextExtraction.fromPage(page), throwsFormatException);
    await document.close();
  });
  test('Automatic ToUnicode handles accents, CJK, supplementary and ligatures',
      () async {
    expect(await extract(), 'ç中😀fi');
    expect(await extract(compressed: true), 'ç中😀fi');
  });
  test('ToUnicode overrides encoding and rejects missing mappings', () async {
    expect(await extract(encoding: 'WinAnsiEncoding'), 'ç中😀fi');
    await expectLater(
        extract(content: 'BT /F1 12 Tf <0005> Tj ET'), throwsFormatException);
  });
  test('Inherited CMaps fail explicitly rather than silently dropping data',
      () async {
    await expectLater(extract(inherited: true), throwsUnsupportedError);
  });
  test('Simple fonts decode WinAnsi accents and Standard quote glyphs',
      () async {
    expect(
        await extract(
            cmap: null,
            encoding: 'WinAnsiEncoding',
            content: 'BT /F1 12 Tf <61E7E36F> Tj ET'),
        'ação');
    expect(
        await extract(cmap: null, content: 'BT /F1 12 Tf <2760> Tj ET'), '’‘');
  });
}
