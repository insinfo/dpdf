import '../pdf_object_wrapper.dart';
import '../pdf_dictionary.dart';

class CraftPdfFileSpec extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  CraftPdfFileSpec(CraftPdfDictionary pdfObject) : super(pdfObject);

  @override
  bool requiresIndirectStorage() => true;
}
