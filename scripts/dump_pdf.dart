import 'dart:io';
import 'dart:convert';

void main() {
  final file = File(r'C:\MyDartProjects\pdfcraft\documento_assinado.pdf');
  if (!file.existsSync()) {
    print('File not found');
    return;
  }
  final bytes = file.readAsBytesSync();
  print('Total Size: ${bytes.length}');
  
  print('--- HEAD ---');
  final head = bytes.sublist(0, bytes.length > 500 ? 500 : bytes.length);
  print(latin1.decode(head, allowInvalid: true));
  
  print('--- TAIL ---');
  final tailLen = 1000;
  final startTail = bytes.length - tailLen < 0 ? 0 : bytes.length - tailLen;
  print(String.fromCharCodes(bytes.sublist(startTail)));
  
  print('--- OFFSET 15 (Obj 4) ---');
  if (bytes.length > 30) {
      print(latin1.decode(bytes.sublist(15, 60), allowInvalid: true));
  }
  
  print('\n--- OFFSET 46 (Obj 1) ---');
  if (bytes.length > 200) {
      print(latin1.decode(bytes.sublist(46, 200), allowInvalid: true));
  }
  
  print('\n--- OFFSET 167 (Obj 2) ---');
   if (bytes.length > 300) {
      print(latin1.decode(bytes.sublist(167, 300), allowInvalid: true));
  }
}
