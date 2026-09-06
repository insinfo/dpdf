import '../pdf_object_wrapper.dart';
import '../pdf_object.dart';
import 'pdf_struct_elem.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';

abstract class CraftPdfMcr extends CraftPdfObjectWrapper<CraftPdfObject>
    implements CraftStructureNode {
  CraftPdfStructElem? parent;

  CraftPdfMcr(CraftPdfObject pdfObject, this.parent) : super(pdfObject);

  Future<int> getMcid();

  Future<CraftPdfDictionary?> getPageObject() async {
    final ref = await getPageIndirectReference();
    if (ref != null) {
      final obj = await ref.targetObject();
      if (obj is CraftPdfDictionary) return obj;
    }
    return null;
  }

  Future<CraftPdfIndirectReference?> getPageIndirectReference() async {
    CraftPdfObject? page;
    if (pdfRepresentation() is CraftPdfDictionary) {
      page = await (pdfRepresentation() as CraftPdfDictionary)
          .get(CraftPdfName('Pg'), false);
    }
    if (page == null && parent != null) {
      page = await parent!.pdfRepresentation().get(CraftPdfName('Pg'), false);
    }

    if (page is CraftPdfIndirectReference) {
      return page;
    } else if (page is CraftPdfDictionary) {
      return page.indirectHandle();
    }
    return null;
  }

  static CraftPdfMcr fromObject(CraftPdfObject obj, CraftPdfStructElem parent) {
    if (obj is CraftPdfNumber) {
      return CraftPdfMcrNumber(obj, parent);
    } else if (obj is CraftPdfDictionary) {
      return CraftPdfMcrDictionary(obj, parent);
    }
    throw ArgumentError('Invalid object type for MCR: ${obj.runtimeType}');
  }

  static Future<CraftPdfMcr?> fromDictionary(
      CraftPdfDictionary dict, CraftPdfStructElem? parent) async {
    return CraftPdfMcrDictionary(dict, parent);
  }

  @override
  Future<CraftPdfName?> getRole() async {
    return parent?.getRole();
  }
}

class CraftPdfMcrNumber extends CraftPdfMcr {
  CraftPdfMcrNumber(CraftPdfNumber pdfObject, CraftPdfStructElem? parent)
      : super(pdfObject, parent);

  @override
  Future<int> getMcid() async {
    return (pdfRepresentation() as CraftPdfNumber).intValue();
  }

  @override
  bool requiresIndirectStorage() => false;
}

class CraftPdfMcrDictionary extends CraftPdfMcr {
  CraftPdfMcrDictionary(
      CraftPdfDictionary pdfObject, CraftPdfStructElem? parent)
      : super(pdfObject, parent);

  @override
  Future<int> getMcid() async {
    final dict = pdfRepresentation() as CraftPdfDictionary;
    final number = await dict.numberEntry(CraftPdfName('MCID'));
    return number?.intValue() ?? -1;
  }

  @override
  bool requiresIndirectStorage() => false;
}

abstract class CraftStructureNode {
  Future<CraftPdfName?> getRole();
}
