import '../pdf_object_wrapper.dart';
import '../pdf_dictionary.dart';
import '../pdf_document.dart';
import '../pdf_name.dart';
import '../pdf_string.dart';
import '../pdf_array.dart';
import '../pdf_object.dart';
import '../pdf_page.dart';
import '../pdf_number.dart';
import 'pdf_mcr.dart';
import 'pdf_namespace.dart';

/// Access to a PDF structure-element dictionary.
///
/// Document semantics are organized as a tree of objects,
/// with a dictionary at its root. The structure tree
/// called the structure tree root (see [PdfStructTreeRoot]). Immediate children of the structure tree root
/// contains structure elements and references to content items.
class CraftPdfStructElem extends CraftPdfObjectWrapper<CraftPdfDictionary>
    implements CraftStructureNode {
  CraftPdfStructElem(CraftPdfDictionary pdfObject) : super(pdfObject) {
    setForbidRelease();
  }

  CraftPdfStructElem.withRole(CraftPdfDocument document, CraftPdfName role)
      : super(CraftPdfDictionary()) {
    attachToDocument(document);
    pdfRepresentation().put(CraftPdfName.type, CraftPdfName.structElem);
    pdfRepresentation().put(CraftPdfName('S'), role);
  }

  CraftPdfStructElem.withRoleAndPage(
      CraftPdfDocument document, CraftPdfName role, CraftPdfPage page)
      : super(CraftPdfDictionary()) {
    attachToDocument(document);
    pdfRepresentation().put(CraftPdfName.type, CraftPdfName.structElem);
    pdfRepresentation().put(CraftPdfName('S'), role);
    // Uses the indirect handle so released objects remain addressable.
    final pageRef = page.pdfRepresentation().indirectHandle();
    if (pageRef != null) {
      pdfRepresentation().put(CraftPdfName('Pg'), pageRef);
    }
  }

  /// Recognizes structure elements among logical-tree entries.
  static Future<bool> isStructElem(CraftPdfDictionary dictionary) async {
    // S is required key of the struct elem
    final type = await dictionary.nameEntry(CraftPdfName.type);
    if (CraftPdfName.structElem == type) {
      return true;
    }
    return dictionary.containsKey(CraftPdfName('S'));
  }

  /// Gets attributes object.
  Future<CraftPdfObject?> getAttributes([bool createNewIfNull = false]) async {
    var attributes = await pdfRepresentation().get(CraftPdfName('A'), true);
    if (attributes == null && createNewIfNull) {
      attributes = CraftPdfDictionary();
      setAttributes(attributes);
    }
    return attributes;
  }

  /// Sets attributes object.
  void setAttributes(CraftPdfObject attributes) {
    put(CraftPdfName('A'), attributes);
  }

  /// Gets the Lang value.
  Future<CraftPdfString?> getLang() async {
    return await pdfRepresentation().stringEntry(CraftPdfName('Lang'));
  }

  /// Sets the Lang value.
  void setLang(CraftPdfString lang) {
    put(CraftPdfName('Lang'), lang);
  }

  /// Gets the Alt (alternative text) value.
  Future<CraftPdfString?> getAlt() async {
    return await pdfRepresentation().stringEntry(CraftPdfName('Alt'));
  }

  /// Sets the Alt (alternative text) value.
  void setAlt(CraftPdfString alt) {
    put(CraftPdfName('Alt'), alt);
  }

  /// Gets the ActualText value.
  Future<CraftPdfString?> getActualText() async {
    return await pdfRepresentation().stringEntry(CraftPdfName('ActualText'));
  }

  /// Sets the ActualText value.
  void setActualText(CraftPdfString actualText) {
    put(CraftPdfName('ActualText'), actualText);
  }

  /// Gets the E (expanded form of abbreviation) value.
  Future<CraftPdfString?> getE() async {
    return await pdfRepresentation().stringEntry(CraftPdfName('E'));
  }

  /// Sets the E (expanded form of abbreviation) value.
  void setE(CraftPdfString e) {
    put(CraftPdfName('E'), e);
  }

  /// Gets the structure element's ID string, if it has one.
  Future<CraftPdfString?> getStructureElementId() async {
    return await pdfRepresentation().stringEntry(CraftPdfName.id);
  }

  /// Gets the role of this structure element.
  @override
  Future<CraftPdfName?> getRole() async {
    return await pdfRepresentation().nameEntry(CraftPdfName('S'));
  }

  /// Sets the role of this structure element.
  void setRole(CraftPdfName role) {
    put(CraftPdfName('S'), role);
  }

  /// Gets the namespace of this structure element.
  Future<CraftPdfNamespace?> getNamespace() async {
    final ns =
        await pdfRepresentation().dictionaryEntry(CraftPdfName.namespace);
    return ns == null ? null : CraftPdfNamespace(ns);
  }

  /// Sets the namespace of this structure element.
  CraftPdfStructElem setNamespace(CraftPdfNamespace? namespace) {
    if (namespace == null) {
      pdfRepresentation().remove(CraftPdfName.namespace);
    } else {
      pdfRepresentation()
          .put(CraftPdfName.namespace, namespace.pdfRepresentation());
    }
    markChanged();
    return this;
  }

  /// Adds a child structure element.
  Future<CraftPdfStructElem> addKid(CraftPdfStructElem kid,
      [int index = -1]) async {
    await _addKidObject(pdfRepresentation(), index, kid.pdfRepresentation());
    return kid;
  }

  /// Removes a child at the given index.
  Future<CraftStructureNode?> removeKid(int index) async {
    final k = await getK();
    if (k == null || (!k.isArray() && index != 0)) {
      return null;
    }
    CraftPdfObject? removedKidObj;
    if (k.isArray()) {
      final kidsArray = k as CraftPdfArray;
      if (index < 0 || index >= kidsArray.size()) return null;
      removedKidObj = await kidsArray.get(index, true);
      if (removedKidObj != null) {
        await kidsArray.remove(removedKidObj);
        if (kidsArray.isEmpty()) {
          pdfRepresentation().remove(CraftPdfName.k);
        }
      }
    } else {
      removedKidObj = k;
      pdfRepresentation().remove(CraftPdfName.k);
    }
    markChanged();
    return removedKidObj != null ? await wrapKid(removedKidObj) : null;
  }

  /// Removes a specific kid object.
  Future<void> removeKidObject(CraftPdfObject kid) async {
    final k = await getK();
    if (k == null) return;
    if (k.isArray()) {
      final kidsArray = k as CraftPdfArray;
      await kidsArray.remove(kid);
      if (kidsArray.isEmpty()) {
        pdfRepresentation().remove(CraftPdfName.k);
      }
    } else {
      if (k == kid) {
        pdfRepresentation().remove(CraftPdfName.k);
      }
    }
    markChanged();
  }

  /// Gets the parent of this structure element.
  Future<CraftStructureNode?> getParent() async {
    final parentObj = await pdfRepresentation().dictionaryEntry(CraftPdfName.p);
    if (parentObj == null) return null;
    if (await isStructElem(parentObj)) {
      return CraftPdfStructElem(parentObj);
    }
    // Could be PdfStructTreeRoot
    if (parentObj.nameEntry(CraftPdfName.type) == CraftPdfName.structTreeRoot) {
      // We lack a way to wrap PdfStructTreeRoot without PdfDocument easily here
      // but it implements IStructureNode.
      // Actually, PdfStructTreeRoot(parentObj) might work if we setDocument later.
      return null; // For now return null or implement a better way
    }
    return null;
  }

  /// Gets list of the direct kids of structure element.
  Future<List<CraftStructureNode>> getKids() async {
    final k = await getK();
    final kids = <CraftStructureNode>[];
    if (k != null) {
      if (k.isArray()) {
        final a = k as CraftPdfArray;
        for (int i = 0; i < a.size(); i++) {
          final kidObj = await a.get(i, true);
          if (kidObj != null) {
            kids.add(await wrapKid(kidObj));
          }
        }
      } else {
        kids.add(await wrapKid(k));
      }
    }
    return kids;
  }

  Future<CraftStructureNode> wrapKid(CraftPdfObject kid) async {
    if (kid is CraftPdfDictionary) {
      if (await isStructElem(kid)) {
        return CraftPdfStructElem(kid);
      } else {
        final mcr = await CraftPdfMcr.fromDictionary(kid, this);
        return mcr!;
      }
    } else if (kid is CraftPdfNumber) {
      return CraftPdfMcr.fromObject(kid, this);
    }
    throw Exception('Unknown kid type: ${kid.runtimeType}');
  }

  /// Gets the K value (kids).
  Future<CraftPdfObject?> getK() async {
    return await pdfRepresentation().get(CraftPdfName.k, true);
  }

  /// Puts a value into the structure element dictionary.
  CraftPdfStructElem put(CraftPdfName key, CraftPdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
    return this;
  }

  @override
  bool requiresIndirectStorage() => true;

  /// Adds a child MCR.
  Future<CraftPdfMcr> addMcr(CraftPdfMcr mcr) async {
    await _addKidObject(pdfRepresentation(), -1, mcr.pdfRepresentation());
    return mcr;
  }

  /// Internal method to add kid object to parent.
  Future<void> _addKidObject(
      CraftPdfDictionary parent, int index, CraftPdfObject kid) async {
    final k = await parent.get(CraftPdfName.k, true);
    if (k == null) {
      if (index == -1) {
        parent.put(CraftPdfName.k, kid);
      } else {
        if (index == 0) {
          parent.put(CraftPdfName.k, kid);
        } else {
          final a = CraftPdfArray();
          a.insert(index, kid);
          parent.put(CraftPdfName.k, a);
        }
      }
    } else {
      CraftPdfArray a;
      if (k is CraftPdfArray) {
        a = k;
      } else {
        a = CraftPdfArray();
        a.add(k);
        parent.put(CraftPdfName.k, a);
      }
      if (index == -1) {
        a.add(kid);
      } else {
        a.insert(index, kid);
      }
    }
    parent.markChanged();
    if (kid is CraftPdfDictionary &&
        await CraftPdfStructElem.isStructElem(kid)) {
      kid.put(CraftPdfName.p, parent);
      kid.markChanged();
    }
  }
}
