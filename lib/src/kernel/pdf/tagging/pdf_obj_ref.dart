import '../pdf_object_wrapper.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import 'pdf_struct_elem.dart';
import 'pdf_mcr.dart';

class CraftPdfObjRef extends CraftPdfObjectWrapper<CraftPdfDictionary>
    implements CraftStructureNode {
  final CraftPdfStructElem parent;

  CraftPdfObjRef(CraftPdfDictionary pdfObject, this.parent) : super(pdfObject);

  @override
  Future<CraftPdfName?> getRole() async {
    return parent.getRole();
  }

  @override
  bool requiresIndirectStorage() => false;
}
