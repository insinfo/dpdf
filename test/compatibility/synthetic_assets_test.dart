import 'dart:io';
import 'package:test/test.dart';
import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';

void main() {
  for (final (file, pages, texts) in [
    ('generated_doc_mdp_allow_signatures.pdf', 1, ['PDF de teste DocMDP']),
    (
      'generated_policy_mandated_timestamp_missing.pdf',
      1,
      ['Generated test PDF']
    ),
    (
      'generated_three_pages.pdf',
      3,
      ['Contract page 1', 'Contract page 2', 'Contract page 3']
    ),
  ]) {
    test('opens and extracts authorized synthetic $file', () async {
      final bytes = await File('test/compatibility/assets/$file').readAsBytes();
      final document =
          await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
      try {
        expect(document.pageTotal(), pages);
        for (var page = 1; page <= pages; page++) {
          expect(
              await PdfTextExtraction.fromPage((await document.pageAt(page))!),
              contains(texts[page - 1]));
        }
      } finally {
        await document.close();
      }
    });
  }
}
