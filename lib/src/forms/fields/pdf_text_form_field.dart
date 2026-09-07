import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_number.dart';
import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/pdf/annot/pdf_widget_annotation.dart';
import 'pdf_form_field.dart';

class CraftPdfTextFormField extends CraftPdfFormField {
  static const int ffMultiline = 1 << 12; // Bit 13
  static const int ffPassword = 1 << 13; // Bit 14
  static const int ffFileSelect = 1 << 20; // Bit 21
  static const int ffDoNotSpellCheck = 1 << 22; // Bit 23
  static const int ffDoNotScroll = 1 << 23; // Bit 24
  static const int ffComb = 1 << 24; // Bit 25
  static const int ffRichText = 1 << 25; // Bit 26

  CraftPdfTextFormField(super.pdfObject);

  @override
  Future<CraftPdfName?> getFormType() async {
    return CraftPdfName.tx;
  }

  static Future<CraftPdfTextFormField> createText(CraftPdfDocument doc,
      [String? fieldName,
      String? value,
      CraftPdfWidgetAnnotation? widget]) async {
    CraftPdfDictionary dict = CraftPdfDictionary();
    dict.put(CraftPdfName.ft, CraftPdfName.tx);

    CraftPdfTextFormField field = CraftPdfTextFormField(dict);
    field.attachToDocument(doc);

    if (fieldName != null) {
      field.setFieldName(fieldName);
    }
    if (value != null) {
      field.setValue(value);
    }
    if (widget != null) {
      await field.addKid(widget);
    }

    return field;
  }

  static Future<CraftPdfTextFormField> createMultilineText(CraftPdfDocument doc,
      [String? fieldName,
      String? value,
      CraftPdfWidgetAnnotation? widget]) async {
    CraftPdfTextFormField field =
        await createText(doc, fieldName, value, widget);
    await field.setMultiline(true);
    return field;
  }

  @override
  Future<bool> isMultiline() async {
    return getFieldFlag(ffMultiline);
  }

  @override
  Future<void> setMultiline(bool multiline) async {
    await setFieldFlag(ffMultiline, multiline);
  }

  @override
  Future<bool> isPassword() async {
    return getFieldFlag(ffPassword);
  }

  @override
  Future<void> setPassword(bool password) async {
    await setFieldFlag(ffPassword, password);
  }

  Future<bool> isFileSelect() async {
    return getFieldFlag(ffFileSelect);
  }

  void setFileSelect(bool fileSelect) {
    setFieldFlag(ffFileSelect, fileSelect);
  }

  Future<bool> isSpellCheck() async {
    return !(await getFieldFlag(ffDoNotSpellCheck));
  }

  void setSpellCheck(bool spellCheck) {
    setFieldFlag(ffDoNotSpellCheck, !spellCheck);
  }

  Future<bool> isScroll() async {
    return !(await getFieldFlag(ffDoNotScroll));
  }

  void setScroll(bool scroll) {
    setFieldFlag(ffDoNotScroll, !scroll);
  }

  Future<bool> isComb() async {
    return getFieldFlag(ffComb);
  }

  void setComb(bool comb) {
    setFieldFlag(ffComb, comb);
  }

  Future<bool> isRichText() async {
    return getFieldFlag(ffRichText);
  }

  void setRichText(bool richText) {
    setFieldFlag(ffRichText, richText);
  }

  Future<int?> getMaxLen() async {
    CraftPdfNumber? num =
        await pdfRepresentation().numberEntry(CraftPdfName.maxLen);
    return num?.intValue();
  }

  void setMaxLen(int maxLen) {
    put(CraftPdfName.maxLen, CraftPdfNumber(maxLen.toDouble()));
  }
}
