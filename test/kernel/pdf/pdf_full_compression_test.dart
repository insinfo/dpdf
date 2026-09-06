import 'dart:io';
import 'package:test/test.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/writer_properties.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

void main() {
  group('PdfFullCompression Test', () {
    late String outPath;

    setUp(() {
      final outDir = Directory('test/tmp');
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
      outPath = 'test/tmp/pdf_full_compression_test.pdf';
    });

    test('Write and Read PDF with Full Compression', () async {
      final writerProperties = WriterProperties().setFullCompressionMode(true);
      final writer = PdfWriter.toFile(outPath, properties: writerProperties);
      final doc = PdfDocument(writer: writer);

    await  doc.addNewPage();

      // Add many small objects (indirect) that should go into ObjStm
      // We can just create them and make them indirect.
      for (int i = 0; i < 50; i++) {
        final dict = PdfDictionary();
        dict.put(PdfName.intern("Key$i"), PdfString("Value$i"));
        dict.makeIndirect(doc);
        // We need to flush them to force writing?
        // PdfDocument auto flushes? No.
        // We can manually flush.
        // Or just let close() flush them? 
        // Objects not attached to the page/catalog might be lost if we don't ref them.
        
        // Let's attach them to the catalog to ensure they are written.
        // Or add to a page resource.
        doc.getCatalog().getPdfObject().put(PdfName.intern("ExtraObject$i"), dict);
      }

      await doc.close();

      // Verification
      final file = File(outPath);
      expect(file.existsSync(), isTrue);
      // Check for /Type /ObjStm string in file content (simple check)
      // final content = await file.readAsString(); // Binary file, cannot read as string safely
      
      // Better: Read with PdfReader and verify objects
      final reader = await PdfReader.fromFile(outPath);
      final docRead = await PdfDocument.open(reader);
      
      expect(docRead.getNumberOfPages(), equals(1));
      
      // Verify objects exist
      final cat = docRead.getCatalog();
      
      for (int i = 0; i < 50; i++) {
        final key = PdfName.intern("ExtraObject$i");
        final obj = await cat.getPdfObject().getAsDictionary(key);
        expect(obj, isNotNull);
        expect(obj is PdfDictionary, isTrue);
        final val = await obj!.get(PdfName.intern("Key$i"));
        expect((val as PdfString).getValue(), equals("Value$i"));
      }
      
      // Verify usage of ObjStm
      // Iterate all objects via xref
      final xref = reader.xref;
      bool foundObjStm = false;
      bool foundInObjStm = false;
      
      for (int i = 0; i < xref.size(); i++) {
        final ref = xref.get(i);
        if (ref != null && !ref.isFree()) {
            final obj = await reader.readObject(i);
            if (obj != null && obj.isStream()) {
                final type = await (obj as PdfDictionary).getAsName(PdfName.type);
                if (type == PdfName.objStm) {
                    foundObjStm = true;
                }
            }
            if (ref.getObjStreamNumber() > 0) {
                foundInObjStm = true;
            }
        }
      }
      
      
      expect(foundObjStm, isTrue, reason: "Should contain at least one Object Stream");
      expect(foundInObjStm, isTrue, reason: "Should have objects inside Object Stream");

      await docRead.close();
    });
  });
}
