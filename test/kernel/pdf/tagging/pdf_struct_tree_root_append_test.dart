import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/stamping_properties.dart';
import 'package:dpdf/src/kernel/pdf/tagging/pdf_struct_elem.dart';
import 'package:test/test.dart';

void main() {
  group('PdfStructTreeRoot Append Mode Tests', () {
    test('Append mode keeps original bytes and updates tag tree', () async {
      final originalBytes = await _createTaggedPdf();

      final appendBuilder = BytesBuilder();
      final appendWriter = PdfWriter.fromBytesBuilder(appendBuilder);
      final reader = PdfReader.fromBytes(originalBytes);
      final props = StampingProperties()..useAppendMode();
      final doc = PdfDocument(reader: reader, writer: appendWriter, properties: props);
      await doc.load();

      final root = await doc.getStructTreeRootAsync();
      expect(root, isNotNull);

      final newElem = PdfStructElem.withRole(doc, PdfName('P'));
      await root!.addKid(newElem);

      await doc.close();

      final appendedBytes = appendBuilder.toBytes();
      expect(appendedBytes.length, greaterThan(originalBytes.length));
      expect(appendedBytes.take(originalBytes.length).toList(), equals(originalBytes));

      final readDoc = PdfDocument.fromReader(PdfReader.fromBytes(appendedBytes));
      await readDoc.load();

      final readRoot = await readDoc.getStructTreeRootAsync();
      expect(readRoot, isNotNull);

      final kids = await readRoot!.getKids();
      expect(kids.length, 2);

      final roles = <PdfName>[];
      for (final kid in kids) {
        expect(kid is PdfDictionary, isTrue);
        final elem = PdfStructElem(kid as PdfDictionary);
        final role = await elem.getRole();
        expect(role, isNotNull);
        roles.add(role!);
      }

      expect(roles, contains(PdfName('Document')));
      expect(roles, contains(PdfName('P')));

      await readDoc.close();
    });
  });
}

Future<Uint8List> _createTaggedPdf() async {
  final builder = BytesBuilder();
  final writer = PdfWriter.fromBytesBuilder(builder);
  final doc = PdfDocument(writer: writer);
  await doc.addNewPage();

  final root = doc.getStructTreeRoot();
  final docElem = PdfStructElem.withRole(doc, PdfName('Document'));
  await root.addKid(docElem);

  await doc.close();
  return builder.toBytes();
}
