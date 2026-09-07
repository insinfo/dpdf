import 'dart:convert';
import 'dart:typed_data';
import 'package:dpdf/dpdf.dart';
import 'package:dpdf/src/kernel/pdf/writer_properties.dart';
import 'package:test/test.dart';

void main() {
  for (final compressed in [false, true]) {
    test('Nested shared streams become indirect, compression=$compressed',
        () async {
      final buffer = BytesBuilder();
      final doc = await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(
          buffer,
          properties:
              CraftWriterProperties().setFullCompressionMode(compressed)));
      final content =
          CraftPdfStream.withBytes(Uint8List.fromList(ascii.encode('q Q')), 0);
      final nested = CraftPdfStream.withBytes(
          Uint8List.fromList(ascii.encode('nested-data')), 0);
      for (var i = 0; i < 2; i++) {
        final page = await doc.appendBlankPage();
        page.pdfRepresentation().put(CraftPdfName.contents, content);
        page.pdfRepresentation().put(
            CraftPdfName.resources,
            CraftPdfDictionary()
              ..put(CraftPdfName('Fixture'), CraftPdfArray.fromList([nested])));
      }
      await doc.close();
      expect(content.indirectHandle(), isNotNull);
      expect(nested.indirectHandle(), isNotNull);
      final bytes = buffer.takeBytes();
      final raw = latin1.decode(bytes);
      // Stream syntax belongs to an indirect object, never a dictionary value.
      expect(RegExp(r'/Contents\s*<<').hasMatch(raw), isFalse);
      final n = content.indirectHandle()!.objectNumber();
      expect(RegExp('$n 0 obj\\s*<<[^>]*>>\\s*stream').hasMatch(raw), isTrue);
      final reopened =
          await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
      final first = await (await reopened.pageAt(1))!.contentSegmentAt(0);
      final second = await (await reopened.pageAt(2))!.contentSegmentAt(0);
      expect(first!.indirectHandle()!.objectNumber(), n);
      expect(second!.indirectHandle()!.objectNumber(), n);
      expect(ascii.decode((await (first as CraftPdfStream).getBytes(false))!),
          'q Q');
      await reopened.close();
    });
  }
}
