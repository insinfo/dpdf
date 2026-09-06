import '../pdf_object_wrapper.dart';
import '../pdf_dictionary.dart';

class PdfFileSpec extends PdfObjectWrapper<PdfDictionary> {
  PdfFileSpec(PdfDictionary pdfObject) : super(pdfObject);

  @override
  bool isWrappedObjectMustBeIndirect() => true;
}
