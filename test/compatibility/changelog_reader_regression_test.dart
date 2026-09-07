import 'dart:convert';
import 'dart:typed_data';
import 'package:pdfcraft/pdfcraft.dart';
import 'package:test/test.dart';

Uint8List pdf(String object,
    {String root = '1 0 R', int generation = 0, String? xrefEntry}) {
  final body = '%PDF-1.7\n1 $generation obj\n$object\nendobj\n';
  return Uint8List.fromList(latin1.encode('$body'
      'xref\n0 2\n0000000000 65535 f \n${xrefEntry ?? '0000000009 ${generation.toString().padLeft(5, '0')} n '}\n'
      'trailer\n<< /Size 2 /Root $root >>\nstartxref\n${body.length}\n%%EOF\n'));
}

void main() {
  for (final root in ['1 0 R', '20 0 R', 'null', '42']) {
    test('Invalid catalog $root fails with a PDF exception, not TypeError',
        () async {
      await expectLater(
          CraftPdfDocument.open(
              CraftPdfReader.fromBytes(pdf('42', root: root))),
          throwsA(isA<CraftPdfException>()));
    });
  }
  test('A stale generation cannot resolve to the current object', () async {
    final reader =
        CraftPdfReader.fromBytes(pdf('<< /Type /Catalog >>', generation: 1));
    await reader.read();
    expect(await reader.rootCatalog(), isNull);
    reader.close();
  });
  test('Matching nonzero generation resolves normally', () async {
    final reader = CraftPdfReader.fromBytes(
        pdf('<< /Type /Catalog >>', generation: 1, root: '1 1 R'));
    await reader.read();
    expect(await reader.rootCatalog(), isNotNull);
    reader.close();
  });
  test('Newest incremental generation wins over the previous xref', () async {
    final base = latin1.decode(pdf('<< /Type /Catalog /Version /Old >>'));
    final previous =
        int.parse(RegExp(r'startxref\n(\d+)').firstMatch(base)!.group(1)!);
    final updated =
        '$base' '1 1 obj\n<< /Type /Catalog /Version /New >>\nendobj\n';
    final source = '$updated'
        'xref\n1 1\n${base.length.toString().padLeft(10, '0')} 00001 n \n'
        'trailer\n<< /Size 2 /Root 1 1 R /Prev $previous >>\nstartxref\n${updated.length}\n%%EOF\n';
    final reader =
        CraftPdfReader.fromBytes(Uint8List.fromList(latin1.encode(source)));
    await reader.read();
    final catalog = await reader.rootCatalog();
    expect((await catalog!.nameEntry(CraftPdfName.version))?.getValue(), 'New');
    expect(reader.xref.get(1)!.generationNumber(), 1);
    reader.close();
  });
  test('Wrong xref object header is rejected explicitly', () async {
    final reader = CraftPdfReader.fromBytes(pdf('<< /Type /Catalog >>',
        generation: 1, xrefEntry: '0000000009 00000 n '));
    await reader.read();
    await expectLater(reader.rootCatalog(), throwsFormatException);
    reader.close();
  });
  test('Malformed xref never claims that reconstruction occurred', () async {
    final source =
        latin1.decode(pdf('42')).replaceFirst('xref\n0 2', 'xref\nBAD');
    final reader =
        CraftPdfReader.fromBytes(Uint8List.fromList(latin1.encode(source)));
    await expectLater(reader.read(), throwsA(isA<CraftPdfException>()));
    expect(reader.rebuiltXref, isFalse);
    reader.close();
  });
  for (final length in [-1, 1000000]) {
    test('Invalid stream length $length produces a format error', () async {
      final reader = CraftPdfReader.fromBytes(
          pdf('<< /Length $length >>\nstream\nx\nendstream'));
      await reader.read();
      await expectLater(reader.readObject(1), throwsFormatException);
      reader.close();
    });
  }
}
