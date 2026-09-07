import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';

/// Demonstrates the restricted Courier editing API on a document created here.
/// Run with an optional output path to save the resulting PDF.
Future<void> main(List<String> args) async {
  final buffer = BytesBuilder();
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(buffer));
  final page = await document.appendBlankPage();
  final font = PdfDictionary()
    ..put(PdfName.type, PdfName.font)
    ..put(PdfName.subtype, PdfName('Type1'))
    ..put(PdfName.baseFont, PdfName('Courier'))
    ..put(PdfName.encoding, PdfName('WinAnsiEncoding'));
  page.pdfRepresentation().put(
      PdfName.resources,
      PdfDictionary()
        ..put(PdfName.font, PdfDictionary()..put(PdfName('F1'), font)));
  page.pdfRepresentation().put(
      PdfName.contents,
      PdfStream.withBytes(
          Uint8List.fromList(ascii.encode(
              'BT /F1 18 Tf 50 750 Td (Cliente: Pedro. Total: 100.) Tj ET')),
          0));
  // This fixture has no metadata by design. Do not strip metadata from an
  // arbitrary input document to circumvent the editing API's validation.
  (await document.documentDetails()).pdfRepresentation().clear();
  await document.close();

  final edited = await PdfTextEditing.replace(
      buffer.takeBytes(), [const PdfTextReplacement(1, 'Pedro', 'João')]);
  final reopened = await PdfDocument.open(PdfReader.fromBytes(edited));
  try {
    stdout
        .writeln(await PdfTextExtraction.fromPage((await reopened.pageAt(1))!));
  } finally {
    await reopened.close();
  }
  if (args.isNotEmpty) await File(args.single).writeAsBytes(edited);
}
