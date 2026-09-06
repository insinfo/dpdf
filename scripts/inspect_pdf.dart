
import 'dart:io';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';

import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';

void main() async {
  final filePath = r'C:\MyDartProjects\pdfcraft\documento_assinado.pdf';
  final file = File(filePath);
  if (!file.existsSync()) {
    print('File not found: $filePath');
    return;
  }

  print('Reading file: ${file.lengthSync()} bytes');
  final bytes = await file.readAsBytes();
  final reader = PdfReader.fromBytes(bytes);
  // Do not call PdfDocument.open(reader) as it crashes
  
  print('Reader created. Reading document structure...');
  await reader.read();
  print('Document structure read.');
  
  final trailer = reader.getTrailer();
  print('Trailer: $trailer');
  
  final rootRef = await trailer?.get(PdfName.root);
  print('Root ref: $rootRef');
  
  if (rootRef == null) {
      print('Root is missing!');
      return;
  }
  
  final rootObj = await reader.readObject((rootRef as PdfIndirectReference).getObjNumber());
  print('Root object: $rootObj');
  
  if (rootObj is! PdfDictionary) {
      print('Root is not a dictionary!');
      return;
  }
  
  final pagesRef = await rootObj.get(PdfName.pages);
  print('Pages ref: $pagesRef');
  
  if (pagesRef is PdfIndirectReference) {
      final pagesObj = await reader.readObject(pagesRef.getObjNumber());
      print('Pages object (read via ref): $pagesObj');
      print('Type: ${pagesObj?.getObjectType()}');
  } else {
      print('Pages is immediate: $pagesRef');
  }
  
  reader.close();
}
