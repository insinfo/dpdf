import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'pdf_action.dart';

class PdfActionURI extends CraftPdfAction {
  PdfActionURI(super.pdfObject);

  static PdfActionURI createURI(String uri) {
    CraftPdfDictionary dict = CraftPdfDictionary();
    dict.put(CraftPdfName.s, CraftPdfName.uri);
    dict.put(CraftPdfName.uri, CraftPdfString(uri));
    return PdfActionURI(dict);
  }

  Future<String?> getUri() async {
    return (await pdfRepresentation().stringEntry(CraftPdfName.uri))
        ?.getValue();
  }
}
