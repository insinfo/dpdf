import '../pdf_object_wrapper.dart';
import '../pdf_object.dart';
import 'pdf_struct_elem.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';

abstract class PdfMcr extends PdfObjectWrapper<PdfObject>
    implements StructureNode {
  PdfStructElem? parent;

  PdfMcr(PdfObject pdfObject, this.parent) : super(pdfObject);

  Future<int> getMcid();

  Future<PdfDictionary?> getPageObject() async {
    final ref = await getPageIndirectReference();
    if (ref != null) {
      final obj = await ref.targetObject();
      if (obj is PdfDictionary) return obj;
    }
    return null;
  }

  Future<PdfIndirectReference?> getPageIndirectReference() async {
    PdfObject? page;
    if (pdfRepresentation() is PdfDictionary) {
      page = await (pdfRepresentation() as PdfDictionary)
          .get(PdfName('Pg'), false);
    }
    if (page == null && parent != null) {
      page = await parent!.pdfRepresentation().get(PdfName('Pg'), false);
    }

    if (page is PdfIndirectReference) {
      return page;
    } else if (page is PdfDictionary) {
      return page.indirectHandle();
    }
    return null;
  }

  static PdfMcr fromObject(PdfObject obj, PdfStructElem parent) {
    if (obj is PdfNumber) {
      return PdfMcrNumber(obj, parent);
    } else if (obj is PdfDictionary) {
      return PdfMcrDictionary(obj, parent);
    }
    throw ArgumentError('Invalid object type for MCR: ${obj.runtimeType}');
  }

  static Future<PdfMcr?> fromDictionary(
      PdfDictionary dict, PdfStructElem? parent) async {
    return PdfMcrDictionary(dict, parent);
  }

  @override
  Future<PdfName?> getRole() async {
    return parent?.getRole();
  }
}

class PdfMcrNumber extends PdfMcr {
  PdfMcrNumber(PdfNumber super.pdfObject, super.parent);

  @override
  Future<int> getMcid() async {
    return (pdfRepresentation() as PdfNumber).intValue();
  }

  @override
  bool requiresIndirectStorage() => false;
}

class PdfMcrDictionary extends PdfMcr {
  PdfMcrDictionary(PdfDictionary super.pdfObject, super.parent);

  @override
  Future<int> getMcid() async {
    final dict = pdfRepresentation() as PdfDictionary;
    final number = await dict.numberEntry(PdfName('MCID'));
    return number?.intValue() ?? -1;
  }

  @override
  bool requiresIndirectStorage() => false;
}

abstract class StructureNode {
  Future<PdfName?> getRole();
}
