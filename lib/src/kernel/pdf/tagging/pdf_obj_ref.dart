import '../pdf_object_wrapper.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';
import '../pdf_page.dart';
import 'pdf_struct_elem.dart';
import 'pdf_mcr.dart';
import 'tagging_names.dart';

/// An object reference: the way a whole PDF object (an annotation, an image
/// or form XObject) becomes a content item of a structure element
/// (ISO 32000-1:2008, 14.7.4.3, Table 325).
class PdfObjRef extends PdfObjectWrapper<PdfDictionary>
    implements StructureNode {
  final PdfStructElem parent;

  PdfObjRef(super.pdfObject, this.parent);

  /// Builds an /OBJR dictionary pointing at [referenced].
  ///
  /// [page] fills the optional /Pg entry, which overrides the /Pg of the
  /// containing structure element.
  factory PdfObjRef.create(PdfObject referenced, PdfStructElem parent,
      {PdfPage? page}) {
    final dictionary = PdfDictionary();
    dictionary.put(PdfName.type, TaggingNames.objr);
    dictionary.put(
        TaggingNames.obj, referenced.indirectHandle() ?? referenced);
    if (page != null) {
      final pageObject = page.pdfRepresentation();
      dictionary.put(
          TaggingNames.pg, pageObject.indirectHandle() ?? pageObject);
    }
    return PdfObjRef(dictionary, parent);
  }

  /// The object this reference denotes (the required /Obj entry).
  Future<PdfObject?> getReferencedObject() async {
    return await pdfRepresentation().get(TaggingNames.obj, true);
  }

  /// The page the referenced object is rendered on, taking the /Pg of the
  /// containing structure element as the fallback.
  Future<PdfIndirectReference?> getPageIndirectReference() async {
    var page = await pdfRepresentation().get(TaggingNames.pg, false);
    page ??= await parent.pdfRepresentation().get(TaggingNames.pg, false);
    if (page is PdfIndirectReference) return page;
    if (page is PdfDictionary) return page.indirectHandle();
    return null;
  }

  @override
  Future<PdfName?> getRole() async {
    return parent.getRole();
  }

  @override
  bool requiresIndirectStorage() => false;
}
