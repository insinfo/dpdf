
import 'dart:io';

void main() async {
  final file = File('documento_assinado_04_02_2026.pdf');
  final bytes = await file.readAsBytes();
  print('Arquivo: ${file.path}');
  print('Tamanho total: ${bytes.length}');

  final content = String.fromCharCodes(bytes);
  final byteRangeMatches = RegExp(r'\/ByteRange\s*\[\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\]').allMatches(content);

  int i = 1;
  for (final match in byteRangeMatches) {
    final r1 = int.parse(match.group(1)!);
    final r2 = int.parse(match.group(2)!);
    final r3 = int.parse(match.group(3)!);
    final r4 = int.parse(match.group(4)!);
    
    print('\nAssinatura #$i:');
    print('  ByteRange: [ $r1 $r2 $r3 $r4 ]');
    print('  Soma r1+r2: ${r1 + r2} (Início da assinatura)');
    print('  Soma r3+r4: ${r3 + r4} (Final do arquivo segundo este range)');
    
    if (r1 + r2 > bytes.length) print('  ERRO: r1+r2 excede o tamanho do arquivo!');
    if (r3 + r4 != bytes.length) {
       print('  AVISO: r3+r4 (${r3 + r4}) não é igual ao tamanho total (${bytes.length})');
    } else {
       print('  OK: r3+r4 bate com o tamanho do arquivo.');
    }
    
    // Verificar se o intervalo [r2, r3] contém o < e > da assinatura
    final signatureHole = bytes.sublist(r2, r3);
    if (signatureHole[0] == 0x3C) { // '<'
       print('  Hole começa com < : OK');
    } else {
       print('  Hole começa com ${signatureHole[0]} (esp: 60) : ERRO');
    }
    if (signatureHole[signatureHole.length - 1] == 0x3E) { // '>'
       print('  Hole termina com > : OK');
    } else {
       print('  Hole termina com ${signatureHole[signatureHole.length - 1]} (esp: 62) : ERRO');
    }
    
    i++;
  }
}
