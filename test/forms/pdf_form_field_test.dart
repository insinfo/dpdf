import 'package:test/test.dart';
import 'package:dpdf/src/forms/fields/pdf_form_field.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

void main() {
  group('PdfFormField Tests', () {
    test('Basic Field Creation and Property Access', () async {
      final dict = PdfDictionary();
      dict.put(PdfName.ft, PdfName.tx);
      dict.put(PdfName.t, PdfString("testField"));

      final field = await PdfFormField.makeFormField(dict, null);

      expect(await field.getFieldNameValue(), "testField");
      expect(await field.getFormType(), PdfName.tx);
    });

    test('Field Flags Manipulation', () async {
      final dict = PdfDictionary();
      final field = await PdfFormField.makeFormField(dict, null);

      expect(await field.getFieldFlag(PdfFormField.ffReadOnly), false);

      await field.setFieldFlag(PdfFormField.ffReadOnly, true);
      expect(await field.getFieldFlag(PdfFormField.ffReadOnly), true);

      await field.setFieldFlag(PdfFormField.ffReadOnly, false);
      expect(await field.getFieldFlag(PdfFormField.ffReadOnly), false);
    });

    test('Field Value Manipulation', () async {
      final dict = PdfDictionary();
      final field = await PdfFormField.makeFormField(dict, null);

      field.setValue("testValue");
      final value = await field.getPdfObject().get(PdfName.v);
      expect(value, isA<PdfString>());
      expect((value as PdfString).toUnicodeString(), "testValue");
    });
  });
}
