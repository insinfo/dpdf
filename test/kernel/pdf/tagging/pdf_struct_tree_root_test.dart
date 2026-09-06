import 'dart:typed_data';
import 'package:pdfcraft/src/kernel/pdf/tagging/pdf_struct_elem.dart';
import 'package:test/test.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_writer.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_reader.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_name.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_dictionary.dart';

void main() {
  group('PdfStructTreeRoot Tests', () {
    test('Add Structure Element with Role', () async {
      // TODO porque não usar arquivo? tem que usar arquivo para ver se esta funcionando corretamente a gravação em arquivo
      // Use BytesBuilder instead of file for more reliable async handling
      final builder = BytesBuilder();
      final writer = CraftPdfWriter.fromBytesBuilder(builder);
      final doc = CraftPdfDocument(writer: writer);
      await doc.appendBlankPage();

      final structTreeRoot = doc.structureRoot();
      final docElem =
          CraftPdfStructElem.withRole(doc, CraftPdfName('Document'));
      final pElem = CraftPdfStructElem.withRole(doc, CraftPdfName('P'));

      await docElem.addKid(pElem);
      await structTreeRoot.addKid(docElem);
      await doc.close();

      final pdfBytes = builder.toBytes();
      expect(pdfBytes.isNotEmpty, isTrue);

      // Verify PDF starts with header
      final headerStr = String.fromCharCodes(pdfBytes.take(8));
      expect(headerStr, startsWith('%PDF-'));

      final reader = CraftPdfReader.fromBytes(pdfBytes);
      final readDoc = await CraftPdfDocument.open(reader);

      final readRoot = await readDoc.loadStructureRoot();
      expect(readRoot, isNotNull);

      final rootK = await readRoot!.getKids();
      expect(rootK.length, 1);

      // getKids returns PdfObject, wrap to PdfStructElem
      final firstKid = rootK[0];
      expect(firstKid is CraftPdfDictionary, isTrue);

      final firstKidElem = CraftPdfStructElem(firstKid as CraftPdfDictionary);
      final role = await firstKidElem.getRole();
      expect(role, equals(CraftPdfName('Document')));

      await readDoc.close();
    });
  });
}
