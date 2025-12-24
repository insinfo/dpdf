import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/pdf/annot/pdf_widget_annotation.dart';
import 'pdf_form_field.dart';

class PdfTextFormField extends PdfFormField {
  PdfTextFormField(PdfDictionary pdfObject) : super(pdfObject);

  // Factory method
  static PdfTextFormField createText(PdfDocument doc,
      [String? fieldName, String? value, PdfWidgetAnnotation? widget]) {
    PdfDictionary dict = PdfDictionary();
    dict.put(PdfName.ft, PdfName.tx);

    PdfTextFormField field = PdfTextFormField(dict);
    field.makeIndirect(doc);

    if (fieldName != null) {
      field.setFieldName(fieldName);
    }
    if (value != null) {
      field.setValue(value);
    }
    if (widget != null) {
      field.addKid(widget);
    }

    return field;
  }
}
