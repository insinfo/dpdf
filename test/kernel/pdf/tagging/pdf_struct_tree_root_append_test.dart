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
      final appendWriter = CraftPdfWriter.fromBytesBuilder(appendBuilder);
      final reader = CraftPdfReader.fromBytes(originalBytes);
      final props = CraftStampingProperties()..useAppendMode();
      final doc = CraftPdfDocument(
          reader: reader, writer: appendWriter, properties: props);
      await doc.load();

      final root = await doc.loadStructureRoot();
      expect(root, isNotNull);

      final newElem = CraftPdfStructElem.withRole(doc, CraftPdfName('P'));
      await root!.addKid(newElem);

      await doc.close();

      final appendedBytes = appendBuilder.toBytes();
      expect(appendedBytes.length, greaterThan(originalBytes.length));
      expect(appendedBytes.take(originalBytes.length).toList(),
          equals(originalBytes));

      final readDoc =
          CraftPdfDocument.fromReader(CraftPdfReader.fromBytes(appendedBytes));
      await readDoc.load();

      final readRoot = await readDoc.loadStructureRoot();
      expect(readRoot, isNotNull);

      final kids = await readRoot!.getKids();
      expect(kids.length, 2);

      final roles = <CraftPdfName>[];
      for (final kid in kids) {
        expect(kid is CraftPdfDictionary, isTrue);
        final elem = CraftPdfStructElem(kid as CraftPdfDictionary);
        final role = await elem.getRole();
        expect(role, isNotNull);
        roles.add(role!);
      }

      expect(roles, contains(CraftPdfName('Document')));
      expect(roles, contains(CraftPdfName('P')));

      await readDoc.close();
    });
  });
}

Future<Uint8List> _createTaggedPdf() async {
  final builder = BytesBuilder();
  final writer = CraftPdfWriter.fromBytesBuilder(builder);
  final doc = CraftPdfDocument(writer: writer);
  await doc.appendBlankPage();

  final root = doc.structureRoot();
  final docElem = CraftPdfStructElem.withRole(doc, CraftPdfName('Document'));
  await root.addKid(docElem);

  await doc.close();
  return builder.toBytes();
}
