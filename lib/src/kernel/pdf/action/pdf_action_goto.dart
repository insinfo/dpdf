import 'package:pdfcraft/src/kernel/pdf/pdf_dictionary.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_name.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_object.dart';
import 'pdf_action.dart';

class PdfActionGoTo extends CraftPdfAction {
  PdfActionGoTo(CraftPdfDictionary pdfObject) : super(pdfObject);

  static PdfActionGoTo createGoTo(CraftPdfObject destination) {
    CraftPdfDictionary dict = CraftPdfDictionary();
    dict.put(CraftPdfName.s, CraftPdfName.goTo);
    dict.put(CraftPdfName.d, destination);
    return PdfActionGoTo(dict);
  }

  Future<CraftPdfObject?> getDestination() async {
    return pdfRepresentation().get(CraftPdfName.d);
  }
}
