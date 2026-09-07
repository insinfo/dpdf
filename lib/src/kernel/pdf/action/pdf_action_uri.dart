import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'pdf_action.dart';

class PdfActionURI extends PdfAction {
  PdfActionURI(super.pdfObject);

  static PdfActionURI createURI(String uri) {
    PdfDictionary dict = PdfDictionary();
    dict.put(PdfName.s, PdfName.uri);
    dict.put(PdfName.uri, PdfString(uri));
    return PdfActionURI(dict);
  }

  Future<String?> getUri() async {
    return (await pdfRepresentation().stringEntry(PdfName.uri))?.getValue();
  }
}
