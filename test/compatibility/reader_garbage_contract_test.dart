import 'dart:typed_data';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_reader.dart';
import 'package:test/test.dart';

void main() {
  final garbage = <String, List<int>>{
    'empty': [],
    'text file': 'this is not a PDF, it is prose'.codeUnits,
    'header only': '%PDF-1.7\n'.codeUnits,
    'header then zeros': [
      ...'%PDF-1.7\n'.codeUnits,
      ...List<int>.filled(4096, 0)
    ],
    'header then letters': [
      ...'%PDF-1.7\n'.codeUnits,
      ...List<int>.filled(4096, 0x41)
    ],
    'one byte': [0x25],
    'truncated xref':
        '%PDF-1.7\nxref\n0 2\n0000000000 65535 f\nstartxref\n9\n%%EOF'
            .codeUnits,
    'out of bounds xref': '%PDF-1.7\nstartxref\n999999\n%%EOF'.codeUnits,
    'negative xref': '%PDF-1.7\nstartxref\n-1\n%%EOF'.codeUnits,
  };
  for (final entry in garbage.entries) {
    test('malformed PDF: ${entry.key} is a recoverable exception', () async {
      await expectLater(() async {
        final reader =
            CraftPdfReader.fromBytes(Uint8List.fromList(entry.value));
        try {
          final document = await CraftPdfDocument.open(reader);
          await document.close();
        } finally {
          reader.close();
        }
      }, throwsA(isA<Exception>()));
    });
  }
}
