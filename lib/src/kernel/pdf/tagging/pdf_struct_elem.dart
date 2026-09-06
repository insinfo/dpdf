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

/// A wrapper for structure element dictionaries (ISO-32000 14.7.2 "Structure Hierarchy").
///
/// The logical structure of a document shall be described by a hierarchy of objects called
/// the structure hierarchy or structure tree. At the root of the hierarchy shall be a dictionary object
/// called the structure tree root (see [PdfStructTreeRoot]). Immediate children of the structure tree root
/// are structure elements. Structure elements are other structure elements or content items.
class PdfStructElem extends PdfObjectWrapper<PdfDictionary> implements IStructureNode {
  PdfStructElem(PdfDictionary pdfObject) : super(pdfObject) {
    setForbidRelease();
  }

  PdfStructElem.withRole(PdfDocument document, PdfName role)
      : super(PdfDictionary()) {
    makeIndirect(document);
    getPdfObject().put(PdfName.type, PdfName.structElem);
    getPdfObject().put(PdfName('S'), role);
  }

  PdfStructElem.withRoleAndPage(
      PdfDocument document, PdfName role, PdfPage page)
      : super(PdfDictionary()) {
    makeIndirect(document);
    getPdfObject().put(PdfName.type, PdfName.structElem);
    getPdfObject().put(PdfName('S'), role);
    // Explicitly using object indirect reference here in order to correctly process released objects.
    final pageRef = page.getPdfObject().getIndirectReference();
    if (pageRef != null) {
      getPdfObject().put(PdfName('Pg'), pageRef);
    }
  }

  /// Method to distinguish struct elements from other elements of the logical tree (like mcr or struct tree root).
  static Future<bool> isStructElem(PdfDictionary dictionary) async {
    // S is required key of the struct elem
    final type = await dictionary.getAsName(PdfName.type);
    if (PdfName.structElem == type) {
      return true;
    }
    return dictionary.containsKey(PdfName('S'));
  }

  /// Gets attributes object.
  Future<PdfObject?> getAttributes([bool createNewIfNull = false]) async {
    var attributes = await getPdfObject().get(PdfName('A'), true);
    if (attributes == null && createNewIfNull) {
      attributes = PdfDictionary();
      setAttributes(attributes);
    }
    return attributes;
  }

  /// Sets attributes object.
  void setAttributes(PdfObject attributes) {
    put(PdfName('A'), attributes);
  }

  /// Gets the Lang value.
  Future<PdfString?> getLang() async {
    return await getPdfObject().getAsString(PdfName('Lang'));
  }

  /// Sets the Lang value.
  void setLang(PdfString lang) {
    put(PdfName('Lang'), lang);
  }

  /// Gets the Alt (alternative text) value.
  Future<PdfString?> getAlt() async {
    return await getPdfObject().getAsString(PdfName('Alt'));
  }

  /// Sets the Alt (alternative text) value.
  void setAlt(PdfString alt) {
    put(PdfName('Alt'), alt);
  }

  /// Gets the ActualText value.
  Future<PdfString?> getActualText() async {
    return await getPdfObject().getAsString(PdfName('ActualText'));
  }

  /// Sets the ActualText value.
  void setActualText(PdfString actualText) {
    put(PdfName('ActualText'), actualText);
  }

  /// Gets the E (expanded form of abbreviation) value.
  Future<PdfString?> getE() async {
    return await getPdfObject().getAsString(PdfName('E'));
  }

  /// Sets the E (expanded form of abbreviation) value.
  void setE(PdfString e) {
    put(PdfName('E'), e);
  }

  /// Gets the structure element's ID string, if it has one.
  Future<PdfString?> getStructureElementId() async {
    return await getPdfObject().getAsString(PdfName.id);
  }

  /// Gets the role of this structure element.
  @override
  Future<PdfName?> getRole() async {
    return await getPdfObject().getAsName(PdfName('S'));
  }

  /// Sets the role of this structure element.
  void setRole(PdfName role) {
    put(PdfName('S'), role);
  }

  /// Gets the namespace of this structure element.
  Future<PdfNamespace?> getNamespace() async {
    final ns = await getPdfObject().getAsDictionary(PdfName.namespace);
    return ns == null ? null : PdfNamespace(ns);
  }

  /// Sets the namespace of this structure element.
  PdfStructElem setNamespace(PdfNamespace? namespace) {
    if (namespace == null) {
      getPdfObject().remove(PdfName.namespace);
    } else {
      getPdfObject().put(PdfName.namespace, namespace.getPdfObject());
    }
    setModified();
    return this;
  }

  /// Adds a child structure element.
  Future<PdfStructElem> addKid(PdfStructElem kid, [int index = -1]) async {
    await _addKidObject(getPdfObject(), index, kid.getPdfObject());
    return kid;
  }

  /// Removes a child at the given index.
  Future<IStructureNode?> removeKid(int index) async {
    final k = await getK();
    if (k == null || (!k.isArray() && index != 0)) {
        return null;
    }
    PdfObject? removedKidObj;
    if (k.isArray()) {
      final kidsArray = k as PdfArray;
      if (index < 0 || index >= kidsArray.size()) return null;
      removedKidObj = await kidsArray.get(index, true);
      if (removedKidObj != null) {
        await kidsArray.remove(removedKidObj);
        if (kidsArray.isEmpty()) {
          getPdfObject().remove(PdfName.k);
        }
      }
    } else {
        removedKidObj = k;
        getPdfObject().remove(PdfName.k);
    }
    setModified();
    return removedKidObj != null ? await wrapKid(removedKidObj) : null;
  }

  /// Removes a specific kid object.
  Future<void> removeKidObject(PdfObject kid) async {
    final k = await getK();
    if (k == null) return;
    if (k.isArray()) {
      final kidsArray = k as PdfArray;
      await kidsArray.remove(kid);
      if (kidsArray.isEmpty()) {
        getPdfObject().remove(PdfName.k);
      }
    } else {
      if (k == kid) {
        getPdfObject().remove(PdfName.k);
      }
    }
    setModified();
  }

  /// Gets the parent of this structure element.
  Future<IStructureNode?> getParent() async {
    final parentObj = await getPdfObject().getAsDictionary(PdfName.p);
    if (parentObj == null) return null;
    if (await isStructElem(parentObj)) {
        return PdfStructElem(parentObj);
    }
    // Could be PdfStructTreeRoot
    if (parentObj.getAsName(PdfName.type) == PdfName.structTreeRoot) {
        // We lack a way to wrap PdfStructTreeRoot without PdfDocument easily here
        // but it implements IStructureNode.
        // Actually, PdfStructTreeRoot(parentObj) might work if we setDocument later.
        return null; // For now return null or implement a better way
    }
    return null;
  }

  /// Gets list of the direct kids of structure element.
  Future<List<IStructureNode>> getKids() async {
    final k = await getK();
    final kids = <IStructureNode>[];
    if (k != null) {
      if (k.isArray()) {
        final a = k as PdfArray;
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

  Future<IStructureNode> wrapKid(PdfObject kid) async {
    if (kid is PdfDictionary) {
      if (await isStructElem(kid)) {
        return PdfStructElem(kid);
      } else {
        final mcr = await PdfMcr.fromDictionary(kid, this);
        return mcr!;
      }
    } else if (kid is PdfNumber) {
      return PdfMcr.fromObject(kid, this);
    }
    throw Exception('Unknown kid type: ${kid.runtimeType}');
  }

  /// Gets the K value (kids).
  Future<PdfObject?> getK() async {
    return await getPdfObject().get(PdfName.k, true);
  }

  /// Puts a value into the structure element dictionary.
  PdfStructElem put(PdfName key, PdfObject value) {
    getPdfObject().put(key, value);
    setModified();
    return this;
  }

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  /// Adds a child MCR.
  Future<PdfMcr> addMcr(PdfMcr mcr) async {
    await _addKidObject(getPdfObject(), -1, mcr.getPdfObject());
    return mcr;
  }

  /// Internal method to add kid object to parent.
  Future<void> _addKidObject(
      PdfDictionary parent, int index, PdfObject kid) async {
    final k = await parent.get(PdfName.k, true);
    if (k == null) {
      if (index == -1) {
        parent.put(PdfName.k, kid);
      } else {
        if (index == 0) {
          parent.put(PdfName.k, kid);
        } else {
          final a = PdfArray();
          a.insert(index, kid);
          parent.put(PdfName.k, a);
        }
      }
    } else {
      PdfArray a;
      if (k is PdfArray) {
        a = k;
      } else {
        a = PdfArray();
        a.add(k);
        parent.put(PdfName.k, a);
      }
      if (index == -1) {
        a.add(kid);
      } else {
        a.insert(index, kid);
      }
    }
    parent.setModified();
    if (kid is PdfDictionary && await PdfStructElem.isStructElem(kid)) {
      kid.put(PdfName.p, parent);
      kid.setModified();
    }
  }
}
