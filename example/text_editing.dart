import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdfcraft/pdfcraft.dart';

/// Demonstrates the restricted Courier editing API on a document created here.
/// Run with an optional output path to save the resulting PDF.
Future<void> main(List<String> args) async {
  final buffer = BytesBuilder();
  final document =
      await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(buffer));
  final page = await document.appendBlankPage();
  final font = CraftPdfDictionary()
    ..put(CraftPdfName.type, CraftPdfName.font)
    ..put(CraftPdfName.subtype, CraftPdfName('Type1'))
    ..put(CraftPdfName.baseFont, CraftPdfName('Courier'))
    ..put(CraftPdfName.encoding, CraftPdfName('WinAnsiEncoding'));
  page.pdfRepresentation().put(
      CraftPdfName.resources,
      CraftPdfDictionary()
        ..put(CraftPdfName.font,
            CraftPdfDictionary()..put(CraftPdfName('F1'), font)));
  page.pdfRepresentation().put(
      CraftPdfName.contents,
      CraftPdfStream.withBytes(
          Uint8List.fromList(ascii.encode(
              'BT /F1 18 Tf 50 750 Td (Cliente: Pedro. Total: 100.) Tj ET')),
          0));
  // This fixture has no metadata by design. Do not strip metadata from an
  // arbitrary input document to circumvent the editing API's validation.
  (await document.documentDetails()).pdfRepresentation().clear();
  await document.close();

  final edited = await PdfTextEditing.replace(
      buffer.takeBytes(), [const PdfTextReplacement(1, 'Pedro', 'João')]);
  final reopened =
      await CraftPdfDocument.open(CraftPdfReader.fromBytes(edited));
  try {
    stdout
        .writeln(await PdfTextExtraction.fromPage((await reopened.pageAt(1))!));
  } finally {
    await reopened.close();
  }
  if (args.isNotEmpty) await File(args.single).writeAsBytes(edited);
}
