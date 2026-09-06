import 'package:test/test.dart';
import 'package:pdfcraft/src/forms/fields/pdf_form_field.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_dictionary.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_name.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_string.dart';

void main() {
  group('PdfFormField Tests', () {
    test('Basic Field Creation and Property Access', () async {
      final dict = CraftPdfDictionary();
      dict.put(CraftPdfName.ft, CraftPdfName.tx);
      dict.put(CraftPdfName.t, CraftPdfString("testField"));

      final field = await CraftPdfFormField.makeFormField(dict, null);

      expect(await field.getFieldNameValue(), "testField");
      expect(await field.getFormType(), CraftPdfName.tx);
    });

    test('Field Flags Manipulation', () async {
      final dict = CraftPdfDictionary();
      final field = await CraftPdfFormField.makeFormField(dict, null);

      expect(await field.getFieldFlag(CraftPdfFormField.ffReadOnly), false);

      await field.setFieldFlag(CraftPdfFormField.ffReadOnly, true);
      expect(await field.getFieldFlag(CraftPdfFormField.ffReadOnly), true);

      await field.setFieldFlag(CraftPdfFormField.ffReadOnly, false);
      expect(await field.getFieldFlag(CraftPdfFormField.ffReadOnly), false);
    });

    test('Field Value Manipulation', () async {
      final dict = CraftPdfDictionary();
      final field = await CraftPdfFormField.makeFormField(dict, null);

      field.setValue("testValue");
      final value = await field.pdfRepresentation().get(CraftPdfName.v);
      expect(value, isA<CraftPdfString>());
      expect((value as CraftPdfString).decodeMappingText(), "testValue");
    });
  });
}
