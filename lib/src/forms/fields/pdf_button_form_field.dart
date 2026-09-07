import '../../kernel/pdf/pdf_object.dart';
import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/annot/pdf_widget_annotation.dart';
import 'pdf_form_field.dart';
import 'pdf_form_annotation.dart';
import '../../kernel/pdf/pdf_string.dart';
import '../../kernel/pdf/pdf_number.dart';
import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/geom/rectangle.dart';

class CraftPdfButtonFormField extends CraftPdfFormField {
  static const int ffNoToggleToOff = 1 << 14; // Bit 15, PDF Spec
  static const int ffRadio = 1 << 15; // Bit 16
  static const int ffPushButton = 1 << 16; // Bit 17
  static const int ffRadiosInUnison = 1 << 25; // Bit 26

  CraftPdfButtonFormField(super.pdfObject);

  // Factory methods to create specific button types (Push, Radio, Checkbox)
  // These are typically in PdfFormCreator in C# but useful to have helpers here or there.

  // Factory methods
  static CraftPdfButtonFormField createRadioGroup(
      CraftPdfDocument document, String name, String? value) {
    CraftPdfDictionary dict = CraftPdfDictionary();
    dict.put(CraftPdfName.ft, CraftPdfName.btn);
    dict.put(CraftPdfName.t, CraftPdfString(name));
    if (value != null) {
      dict.put(CraftPdfName.v, CraftPdfName(value));
    }
    dict.put(CraftPdfName.ff, CraftPdfNumber(ffRadio.toDouble()));

    CraftPdfButtonFormField field = CraftPdfButtonFormField(dict);
    field.attachToDocument(document);
    return field;
  }

  static Future<CraftPdfWidgetAnnotation> createRadioButton(
      CraftPdfDocument document,
      CraftRectangle rect,
      CraftPdfButtonFormField group,
      String value) async {
    CraftPdfWidgetAnnotation widget = CraftPdfWidgetAnnotation.fromRect(rect);
    widget.put(CraftPdfName.as, CraftPdfName(value));
    widget.pdfRepresentation().attachToDocument(document);

    await group.addKid(widget);

    return widget;
  }

  @override
  Future<CraftPdfName?> getFormType() async {
    return CraftPdfName.btn;
  }

  Future<bool> isRadio() async {
    return getFieldFlag(ffRadio);
  }

  void setRadio(bool radio) {
    setFieldFlag(ffRadio, radio);
  }

  Future<bool> isToggleOff() async {
    return !(await getFieldFlag(ffNoToggleToOff));
  }

  void setToggleOff(bool toggleOff) {
    setFieldFlag(ffNoToggleToOff, !toggleOff);
  }

  Future<bool> isPushButton() async {
    return getFieldFlag(ffPushButton);
  }

  void setPushButton(bool pushButton) {
    setFieldFlag(ffPushButton, pushButton);
  }

  Future<bool> isRadiosInUnison() async {
    return getFieldFlag(ffRadiosInUnison);
  }

  void setRadiosInUnison(bool radiosInUnison) {
    setFieldFlag(ffRadiosInUnison, radiosInUnison);
  }

  @override
  Future<void> addKid(CraftPdfWidgetAnnotation kid) async {
    await super.addKid(kid);

    if (await isRadio()) {
      CraftPdfName? appearanceState =
          await kid.pdfRepresentation().nameEntry(CraftPdfName.as);
      CraftPdfObject? valueObj =
          await pdfRepresentation().get(CraftPdfName.v, true);

      if (appearanceState != null && appearanceState != valueObj) {
        kid.pdfRepresentation().put(CraftPdfName.as, CraftPdfName("Off"));
      }

      CraftPdfFormAnnotation formAnnot =
          CraftPdfFormAnnotation(kid.pdfRepresentation());
      await formAnnot.drawRadioButtonAndSaveAppearance(
          appearanceState?.getValue() ?? "Yes");
    }
  }
}
