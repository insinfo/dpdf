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

class PdfButtonFormField extends PdfFormField {
  static const int ffNoToggleToOff = 1 << 14; // Bit 15, PDF Spec
  static const int ffRadio = 1 << 15; // Bit 16
  static const int ffPushButton = 1 << 16; // Bit 17
  static const int ffRadiosInUnison = 1 << 25; // Bit 26

  PdfButtonFormField(PdfDictionary pdfObject) : super(pdfObject);

  // Factory methods to create specific button types (Push, Radio, Checkbox)
  // These are typically in PdfFormCreator in C# but useful to have helpers here or there.

  // Factory methods
  static PdfButtonFormField createRadioGroup(
      PdfDocument document, String name, String? value) {
    PdfDictionary dict = PdfDictionary();
    dict.put(PdfName.ft, PdfName.btn);
    dict.put(PdfName.t, PdfString(name));
    if (value != null) {
      dict.put(PdfName.v, PdfName(value));
    }
    dict.put(PdfName.ff, PdfNumber(ffRadio.toDouble()));

    PdfButtonFormField field = PdfButtonFormField(dict);
    field.makeIndirect(document);
    return field;
  }

  static Future<PdfWidgetAnnotation> createRadioButton(PdfDocument document,
      Rectangle rect, PdfButtonFormField group, String value) async {
    PdfWidgetAnnotation widget = PdfWidgetAnnotation.fromRect(rect);
    widget.put(PdfName.as, PdfName(value));

    await group.addKid(widget);

    return widget;
  }

  @override
  Future<PdfName?> getFormType() async {
    return PdfName.btn;
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
  Future<void> addKid(PdfWidgetAnnotation kid) async {
    await super.addKid(kid);

    if (await isRadio()) {
      PdfName? appearanceState = await kid.getPdfObject().getAsName(PdfName.as);
      PdfObject? valueObj = await getPdfObject().get(PdfName.v, true);

      if (appearanceState != null &&
          valueObj is PdfName &&
          appearanceState != valueObj) {
        kid.getPdfObject().put(PdfName.as, PdfName("Off"));
      }

      PdfFormAnnotation formAnnot = PdfFormAnnotation(kid.getPdfObject());
      await formAnnot.drawRadioButtonAndSaveAppearance(
          appearanceState?.getValue() ?? "Yes");
    }
  }
}
