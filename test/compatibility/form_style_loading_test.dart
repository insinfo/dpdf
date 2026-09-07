import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';
import 'form_merge_policy_test.dart' as fixtures;

void main() {
  test(
      'Loaded merged fields finish appearance reads before enumeration returns',
      () async {
    final input = await fixtures.source(resources: true);
    final merged = await PdfPageAssembly.merge([
      PdfPageSelection(input),
      PdfPageSelection(input),
      PdfPageSelection(input)
    ], preserveForms: true);
    final document =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(merged));
    try {
      final form = await CraftPdfAcroForm.getAcroForm(document, false);
      final fields = await form.getAllFormFields();
      expect(fields.keys, containsAll(['nome', 'nome_2', 'nome_3']));
      for (final field in fields.values) {
        expect(field.getFontSize(), 12);
        expect(field.resolveTypeface(), isNotNull);
        expect(await field.getFieldNameValue(), isNotEmpty);
        await field.loadStyles();
      }
      expect((await form.getField('nome_2'))!.getFontSize(), 12);
      expect((await document.pageAt(3))!, isNotNull);
    } finally {
      await document.close();
    }
  });
}
