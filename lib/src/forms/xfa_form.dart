// import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_object.dart';

class XfaForm {
  PdfObject? xfaObject;

  XfaForm(PdfObject? xfaObject) {
    this.xfaObject = xfaObject;
  }

  XfaForm.fromDocument(PdfDocument document) {
    // TODO ...
  }
}
