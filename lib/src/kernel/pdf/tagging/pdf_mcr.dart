import '../pdf_object_wrapper.dart';
import '../pdf_object.dart';
import 'pdf_struct_elem.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_page.dart';
import '../pdf_stream.dart';
import 'tagging_names.dart';

/// A reference, from the logical structure, to a marked-content sequence
/// inside a content stream (ISO 32000-1:2008, 14.7.4.2, Table 324).
///
/// Two shapes are allowed by the specification and both are modelled here:
/// a bare integer marked-content identifier ([PdfMcrNumber]) and a
/// marked-content reference dictionary ([PdfMcrDictionary]).
abstract class PdfMcr extends PdfObjectWrapper<PdfObject>
    implements StructureNode {
  PdfStructElem? parent;

  PdfMcr(super.pdfObject, this.parent);

  /// The marked-content identifier of the sequence this reference denotes.
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
      page =
          await (pdfRepresentation() as PdfDictionary).get(TaggingNames.pg, false);
    }
    if (page == null && parent != null) {
      page = await parent!.pdfRepresentation().get(TaggingNames.pg, false);
    }

    if (page is PdfIndirectReference) {
      return page;
    } else if (page is PdfDictionary) {
      return page.indirectHandle();
    }
    return null;
  }

  /// The content stream holding the sequence, when it is not the page's own
  /// content stream (the /Stm entry of Table 324).
  Future<PdfStream?> getContentStream() async {
    final self = pdfRepresentation();
    if (self is PdfDictionary) {
      return await self.streamEntry(TaggingNames.stm);
    }
    return null;
  }

  /// The object owning the stream named by /Stm (the /StmOwn entry).
  Future<PdfObject?> getContentStreamOwner() async {
    final self = pdfRepresentation();
    if (self is PdfDictionary) {
      return await self.get(TaggingNames.stmOwn, true);
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

/// The compact form of a marked-content reference: a bare integer used when
/// the sequence lives in the content stream of the page named by the parent
/// element's /Pg entry (ISO 32000-1:2008, 14.7.4.2).
class PdfMcrNumber extends PdfMcr {
  PdfMcrNumber(PdfNumber super.pdfObject, super.parent);

  PdfMcrNumber.withMcid(int mcid, PdfStructElem? parent)
      : super(PdfNumber.fromInt(mcid), parent);

  @override
  Future<int> getMcid() async {
    return (pdfRepresentation() as PdfNumber).intValue();
  }

  @override
  bool requiresIndirectStorage() => false;
}

/// The dictionary form of a marked-content reference (Table 324). It is
/// required whenever the sequence does not live in the page content stream
/// named by the parent element, or when the page has to be overridden.
class PdfMcrDictionary extends PdfMcr {
  PdfMcrDictionary(PdfDictionary super.pdfObject, super.parent);

  /// Builds a /MCR dictionary for [mcid] rendered on [page].
  ///
  /// [stream] names the content stream when the sequence does not belong to
  /// the page content stream; [streamOwner] names the object owning it (for
  /// example the annotation an appearance stream belongs to).
  factory PdfMcrDictionary.create(PdfPage page, int mcid,
      {PdfStructElem? parent, PdfStream? stream, PdfObject? streamOwner}) {
    final dictionary = PdfDictionary();
    dictionary.put(PdfName.type, TaggingNames.mcr);
    final pageRef = page.pdfRepresentation().indirectHandle();
    dictionary.put(
        TaggingNames.pg, pageRef ?? page.pdfRepresentation());
    if (stream != null) {
      dictionary.put(TaggingNames.stm, stream.indirectHandle() ?? stream);
    }
    if (streamOwner != null) {
      dictionary.put(
          TaggingNames.stmOwn, streamOwner.indirectHandle() ?? streamOwner);
    }
    dictionary.put(TaggingNames.mcid, PdfNumber.fromInt(mcid));
    return PdfMcrDictionary(dictionary, parent);
  }

  @override
  Future<int> getMcid() async {
    final dict = pdfRepresentation() as PdfDictionary;
    final number = await dict.numberEntry(TaggingNames.mcid);
    return number?.intValue() ?? -1;
  }

  @override
  bool requiresIndirectStorage() => false;
}

/// Anything that can appear as a node of the logical structure: a structure
/// element, a marked-content reference or an object reference.
abstract class StructureNode {
  Future<PdfName?> getRole();
}
