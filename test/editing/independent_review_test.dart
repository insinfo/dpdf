import 'dart:convert';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_copier.dart';
import 'text_redaction_test.dart' as fixture;

void main() {
  test('Redaction writes decimal PDF numbers and preserves tiny advances',
      () async {
    const content = 'BT /F1 .0000001 Tf .00000001 Tc (ABC) Tj ET';
    final input = await fixture.fixture([content]);
    final result =
        await PdfTextRedaction.remove(input, [const PdfTextRemoval(1, 'B')]);
    final document = await PdfDocument.open(PdfReader.fromBytes(result));
    final page = (await document.pageAt(1))!;
    final bytes =
        await (await page.contentSegmentAt(0) as PdfStream).getBytes();
    final output = ascii.decode(bytes!);
    expect(RegExp(r'[0-9][eE][+-]?[0-9]').hasMatch(output), isFalse,
        reason: output);
    final before = fixture.positions(fixture.bytes(content));
    final after = fixture.positions(bytes);
    expect(after.map((c) => c.text).join(), 'AC');
    expect(after[1].x, closeTo(before[2].x, 1e-20));
    await document.close();
  });
  test('Non-PDF exponents and overflowing derived positions fail closed', () {
    expect(() => fixture.positions(fixture.bytes('BT /F1 1e2 Tf (A) Tj ET')),
        throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())));
    final large = '1${'0' * 200}';
    expect(
        () => fixture.positions(fixture
            .bytes('$large 0 0 $large 0 0 cm BT /F1 $large Tf (A) Tj ET')),
        throwsFormatException);
  });
  test('Object copier rejects cyclic indirect-reference chains', () async {
    final output =
        PdfDocument.create(PdfWriter.fromBytesBuilder(BytesBuilder()));
    final a = PdfIndirectReference(101), b = PdfIndirectReference(102);
    a.assignTargetObject(b);
    b.assignTargetObject(a);
    await expectLater(PdfObjectCopier(output).copy(a), throwsFormatException);
    await output.close();
  });
}
