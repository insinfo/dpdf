import '../pdf_object_wrapper.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import 'pdf_struct_elem.dart';
import 'pdf_mcr.dart';

class PdfObjRef extends PdfObjectWrapper<PdfDictionary> implements IStructureNode {
  final PdfStructElem parent;

  PdfObjRef(PdfDictionary pdfObject, this.parent) : super(pdfObject);

  @override
  Future<PdfName?> getRole() async {
    return parent.getRole();
  }

  @override
  bool isWrappedObjectMustBeIndirect() => false;
}
