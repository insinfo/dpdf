import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/annot/pdf_widget_annotation.dart';
import 'abstract_pdf_form_field.dart';

class PdfFormAnnotation extends AbstractPdfFormField {
  PdfFormAnnotation(PdfDictionary pdfObject) : super(pdfObject);

  PdfWidgetAnnotation getWidget() {
    return PdfWidgetAnnotation(getPdfObject());
  }

  @override
  Future<bool> regenerateField() async {
    // TODO: Implement appearance regeneration
    return false;
  }

  @override
  Future<List<String>> getAppearanceStates() async {
    final ap = await getPdfObject().getAsDictionary(PdfName.ap);
    if (ap == null) return [];

    final n = await ap.getAsDictionary(PdfName.n);
    if (n == null) return [];

    return n.keySet().map((e) => e.getValue()).toList();
  }
}
