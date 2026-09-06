import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'pdf_action.dart';

class PdfActionGoTo extends PdfAction {
  PdfActionGoTo(PdfDictionary pdfObject) : super(pdfObject);

  static PdfActionGoTo createGoTo(PdfObject destination) {
    PdfDictionary dict = PdfDictionary();
    dict.put(PdfName.s, PdfName.goTo);
    dict.put(PdfName.d, destination);
    return PdfActionGoTo(dict);
  }

  Future<PdfObject?> getDestination() async {
    return getPdfObject().get(PdfName.d);
  }
}
