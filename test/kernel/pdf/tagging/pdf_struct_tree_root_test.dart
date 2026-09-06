import 'dart:typed_data';
import 'package:dpdf/src/kernel/pdf/tagging/pdf_struct_elem.dart';
import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';

void main() {
  group('PdfStructTreeRoot Tests', () {
    test('Add Structure Element with Role', () async {
      // TODO porque não usar arquivo? tem que usar arquivo para ver se esta funcionando corretamente a gravação em arquivo
      // Use BytesBuilder instead of file for more reliable async handling
      final builder = BytesBuilder();
      final writer = PdfWriter.fromBytesBuilder(builder);
      final doc = PdfDocument(writer: writer);
      await doc.addNewPage();

      final structTreeRoot = doc.getStructTreeRoot();
      final docElem = PdfStructElem.withRole(doc, PdfName('Document'));
      final pElem = PdfStructElem.withRole(doc, PdfName('P'));

      await docElem.addKid(pElem);
      await structTreeRoot.addKid(docElem);
      await doc.close();

      final pdfBytes = builder.toBytes();
      expect(pdfBytes.isNotEmpty, isTrue);
      
      // Verify PDF starts with header
      final headerStr = String.fromCharCodes(pdfBytes.take(8));
      expect(headerStr, startsWith('%PDF-'));

      final reader = PdfReader.fromBytes(pdfBytes);
      final readDoc = await PdfDocument.open(reader);
      
      final readRoot = await readDoc.getStructTreeRootAsync();
      expect(readRoot, isNotNull);

      final rootK = await readRoot!.getKids();
      expect(rootK.length, 1);
      
      // getKids returns PdfObject, wrap to PdfStructElem
      final firstKid = rootK[0];
      expect(firstKid is PdfDictionary, isTrue);
      
      final firstKidElem = PdfStructElem(firstKid as PdfDictionary);
      final role = await firstKidElem.getRole();
      expect(role, equals(PdfName('Document')));

      await readDoc.close();
    });
  });
}
