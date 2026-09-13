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
import 'pdf_obj_ref.dart';
import 'pdf_namespace.dart';
import 'pdf_struct_tree_root.dart';
import 'tagging_names.dart';

/// Access to a PDF structure-element dictionary
/// (ISO 32000-1:2008, 14.7.2, Table 323).
///
/// Document semantics are organized as a tree of objects rooted at the
/// structure tree root (see [PdfStructTreeRoot]). Immediate children of the
/// structure tree root are structure elements; a structure element's own
/// children are further structure elements and references to content items.
class PdfStructElem extends PdfObjectWrapper<PdfDictionary>
    implements StructureNode {
  PdfStructElem(super.pdfObject) {
    setForbidRelease();
  }

  PdfStructElem.withRole(PdfDocument document, PdfName role)
      : super(PdfDictionary()) {
    attachToDocument(document);
    pdfRepresentation().put(PdfName.type, PdfName.structElem);
    pdfRepresentation().put(PdfName.s, role);
    setForbidRelease();
  }

  PdfStructElem.withRoleAndPage(
      PdfDocument document, PdfName role, PdfPage page)
      : super(PdfDictionary()) {
    attachToDocument(document);
    pdfRepresentation().put(PdfName.type, PdfName.structElem);
    pdfRepresentation().put(PdfName.s, role);
    // Uses the indirect handle so released objects remain addressable.
    final pageRef = page.pdfRepresentation().indirectHandle();
    if (pageRef != null) {
      pdfRepresentation().put(TaggingNames.pg, pageRef);
    }
    setForbidRelease();
  }

  /// Recognizes structure elements among logical-tree entries.
  static Future<bool> isStructElem(PdfDictionary dictionary) async {
    // S is a required key of a structure element.
    final type = await dictionary.nameEntry(PdfName.type);
    if (PdfName.structElem == type) {
      return true;
    }
    if (TaggingNames.mcr == type || TaggingNames.objr == type) {
      return false;
    }
    return dictionary.containsKey(PdfName.s);
  }

  // ---------------------------------------------------------------- S and NS

  /// Gets the structure type of this element (the required /S entry).
  @override
  Future<PdfName?> getRole() async {
    return await pdfRepresentation().nameEntry(PdfName.s);
  }

  /// Sets the structure type of this element.
  void setRole(PdfName role) {
    put(PdfName.s, role);
  }

  /// Gets the namespace of this structure element (PDF 2.0 /NS).
  Future<PdfNamespace?> getNamespace() async {
    final ns = await pdfRepresentation().dictionaryEntry(PdfName.namespace);
    return ns == null ? null : PdfNamespace(ns);
  }

  /// Sets the namespace of this structure element.
  PdfStructElem setNamespace(PdfNamespace? namespace) {
    if (namespace == null) {
      pdfRepresentation().remove(PdfName.namespace);
    } else {
      pdfRepresentation().put(PdfName.namespace, namespace.pdfRepresentation());
    }
    markChanged();
    return this;
  }

  // -------------------------------------------------------------------- Pg

  /// Gets the page some or all of this element's content items live on.
  Future<PdfDictionary?> getPageObject() async {
    return await pdfRepresentation().dictionaryEntry(TaggingNames.pg);
  }

  /// Sets the page some or all of this element's content items live on.
  PdfStructElem setPage(PdfPage page) {
    final pageObject = page.pdfRepresentation();
    return put(TaggingNames.pg, pageObject.indirectHandle() ?? pageObject);
  }

  // ----------------------------------------------------- A: attribute objects

  /// Gets the raw /A value, creating an empty attribute dictionary when
  /// [createNewIfNull] is set.
  Future<PdfObject?> getAttributes([bool createNewIfNull = false]) async {
    var attributes = await pdfRepresentation().get(PdfName.a, true);
    if (attributes == null && createNewIfNull) {
      attributes = PdfDictionary();
      setAttributes(attributes);
    }
    return attributes;
  }

  /// Replaces the whole /A value.
  void setAttributes(PdfObject attributes) {
    put(PdfName.a, attributes);
  }

  /// Gets every attribute object attached through /A, dropping the interleaved
  /// revision numbers described in 14.7.5.3.
  Future<List<PdfObject>> getAttributesList() async {
    final attributes = await pdfRepresentation().get(PdfName.a, true);
    final result = <PdfObject>[];
    if (attributes == null) return result;
    if (attributes is PdfArray) {
      for (var i = 0; i < attributes.size(); i++) {
        final item = await attributes.get(i, true);
        if (item == null || item is PdfNumber) continue;
        result.add(item);
      }
    } else {
      result.add(attributes);
    }
    return result;
  }

  /// Attaches [attribute] to this element with the given [revision]
  /// (ISO 32000-1:2008, 14.7.5.1 and 14.7.5.3).
  ///
  /// A single attribute object without a revision is stored directly; the
  /// value is promoted to an array as soon as a second object or a non-zero
  /// revision has to be recorded.
  Future<void> addAttribute(PdfObject attribute, {int revision = 0}) async {
    if (revision < 0) {
      throw ArgumentError.value(
          revision, 'revision', 'A revision number cannot be negative.');
    }
    final current = await pdfRepresentation().get(PdfName.a, true);
    if (current == null && revision == 0) {
      put(PdfName.a, attribute);
      return;
    }
    final array = current is PdfArray ? current : PdfArray();
    if (current != null && current is! PdfArray) {
      array.add(current);
    }
    array.add(attribute);
    if (revision != 0) {
      array.add(PdfNumber.fromInt(revision));
    }
    put(PdfName.a, array);
  }

  /// The revision number recorded for [attribute] in the /A array; 0 when the
  /// object carries no explicit revision.
  Future<int> getAttributeRevision(PdfObject attribute) async {
    final current = await pdfRepresentation().get(PdfName.a, true);
    if (current is! PdfArray) return 0;
    for (var i = 0; i < current.size(); i++) {
      final item = await current.get(i, true);
      if (item is PdfNumber) continue;
      if (!identical(item, attribute)) continue;
      final next = await current.get(i + 1, true);
      return next is PdfNumber ? next.intValue() : 0;
    }
    return 0;
  }

  /// Detaches [attribute] together with its revision number, if any.
  Future<bool> removeAttribute(PdfObject attribute) async {
    final current = await pdfRepresentation().get(PdfName.a, true);
    if (current == null) return false;
    if (current is! PdfArray) {
      if (!identical(current, attribute)) return false;
      pdfRepresentation().remove(PdfName.a);
      markChanged();
      return true;
    }
    for (var i = 0; i < current.size(); i++) {
      final item = await current.get(i, true);
      if (item is PdfNumber) continue;
      if (!identical(item, attribute)) continue;
      final next = await current.get(i + 1, true);
      if (next is PdfNumber) {
        current.removeAt(i + 1);
      }
      current.removeAt(i);
      if (current.isEmpty()) {
        pdfRepresentation().remove(PdfName.a);
      }
      markChanged();
      return true;
    }
    return false;
  }

  // -------------------------------------------------- C: attribute class names

  /// Gets the attribute class names attached through /C (14.7.5.2).
  Future<List<PdfName>> getAttributeClasses() async {
    final current = await pdfRepresentation().get(PdfName.c, true);
    final result = <PdfName>[];
    if (current == null) return result;
    if (current is PdfArray) {
      for (var i = 0; i < current.size(); i++) {
        final item = await current.get(i, true);
        if (item is PdfName) result.add(item);
      }
    } else if (current is PdfName) {
      result.add(current);
    }
    return result;
  }

  /// Attaches the attribute class [className] with the given [revision].
  Future<void> addAttributeClass(PdfName className, {int revision = 0}) async {
    if (revision < 0) {
      throw ArgumentError.value(
          revision, 'revision', 'A revision number cannot be negative.');
    }
    final current = await pdfRepresentation().get(PdfName.c, true);
    if (current == null && revision == 0) {
      put(PdfName.c, className);
      return;
    }
    final array = current is PdfArray ? current : PdfArray();
    if (current != null && current is! PdfArray) {
      array.add(current);
    }
    array.add(className);
    if (revision != 0) {
      array.add(PdfNumber.fromInt(revision));
    }
    put(PdfName.c, array);
  }

  /// The revision number recorded for the attribute class [className].
  Future<int> getAttributeClassRevision(PdfName className) async {
    final current = await pdfRepresentation().get(PdfName.c, true);
    if (current is! PdfArray) return 0;
    for (var i = 0; i < current.size(); i++) {
      final item = await current.get(i, true);
      if (item != className) continue;
      final next = await current.get(i + 1, true);
      return next is PdfNumber ? next.intValue() : 0;
    }
    return 0;
  }

  // --------------------------------------------------------------------- R

  /// The current revision number of this structure element (14.7.5.3).
  /// An absent /R means revision 0.
  Future<int> getRevision() async {
    return (await pdfRepresentation().numberEntry(PdfName.r))?.intValue() ?? 0;
  }

  /// Sets the revision number of this structure element.
  PdfStructElem setRevision(int revision) {
    if (revision < 0) {
      throw ArgumentError.value(
          revision, 'revision', 'A revision number cannot be negative.');
    }
    return put(PdfName.r, PdfNumber.fromInt(revision));
  }

  /// Bumps the revision number, materializing /R when it was defaulted to 0.
  Future<int> incrementRevision() async {
    final next = await getRevision() + 1;
    setRevision(next);
    return next;
  }

  // ------------------------------------------------ text and language entries

  /// Gets the /T title of the structure element.
  Future<PdfString?> getTitle() async {
    return await pdfRepresentation().stringEntry(PdfName.t);
  }

  /// Sets the /T title of the structure element.
  void setTitle(PdfString title) {
    put(PdfName.t, title);
  }

  /// Gets the Lang value.
  Future<PdfString?> getLang() async {
    return await pdfRepresentation().stringEntry(TaggingNames.lang);
  }

  /// Sets the Lang value.
  void setLang(PdfString lang) {
    put(TaggingNames.lang, lang);
  }

  /// Gets the Alt (alternative text) value.
  Future<PdfString?> getAlt() async {
    return await pdfRepresentation().stringEntry(TaggingNames.alt);
  }

  /// Sets the Alt (alternative text) value.
  void setAlt(PdfString alt) {
    put(TaggingNames.alt, alt);
  }

  /// Gets the ActualText value.
  Future<PdfString?> getActualText() async {
    return await pdfRepresentation().stringEntry(TaggingNames.actualText);
  }

  /// Sets the ActualText value.
  void setActualText(PdfString actualText) {
    put(TaggingNames.actualText, actualText);
  }

  /// Gets the E (expanded form of abbreviation) value.
  Future<PdfString?> getE() async {
    return await pdfRepresentation().stringEntry(TaggingNames.e);
  }

  /// Sets the E (expanded form of abbreviation) value.
  void setE(PdfString e) {
    put(TaggingNames.e, e);
  }

  // -------------------------------------------------------------------- ID

  /// Gets the structure element's ID string, if it has one.
  Future<PdfString?> getStructureElementId() async {
    return await pdfRepresentation().stringEntry(PdfName.id);
  }

  /// Sets the element identifier and records it in the structure tree root's
  /// /IDTree, which Table 322 requires whenever any element carries an /ID.
  Future<void> setStructureElementId(PdfString id) async {
    final previous = await getStructureElementId();
    final root = await _structTreeRoot();
    if (previous != null && root != null) {
      await root.removeElementId(previous);
    }
    put(PdfName.id, id);
    if (root != null) {
      await root.registerElementId(id, this);
    }
  }

  /// Drops the element identifier and its /IDTree entry.
  Future<void> removeStructureElementId() async {
    final previous = await getStructureElementId();
    if (previous == null) return;
    pdfRepresentation().remove(PdfName.id);
    markChanged();
    final root = await _structTreeRoot();
    await root?.removeElementId(previous);
  }

  Future<PdfStructTreeRoot?> _structTreeRoot() async {
    final document = getDocument();
    if (document == null) return null;
    return await document.loadStructureRoot();
  }

  // ----------------------------------------------------------------- K and P

  /// Adds a child structure element.
  Future<PdfStructElem> addKid(PdfStructElem kid, [int index = -1]) async {
    await _addKidObject(pdfRepresentation(), index, kid.pdfRepresentation());
    return kid;
  }

  /// Adds a marked-content reference as a content item of this element.
  Future<PdfMcr> addMcr(PdfMcr mcr, [int index = -1]) async {
    mcr.parent = this;
    await _addKidObject(pdfRepresentation(), index, mcr.pdfRepresentation());
    return mcr;
  }

  /// Adds an object reference as a content item of this element.
  Future<PdfObjRef> addObjRef(PdfObjRef objRef, [int index = -1]) async {
    await _addKidObject(pdfRepresentation(), index, objRef.pdfRepresentation());
    return objRef;
  }

  /// Removes a child at the given index.
  Future<StructureNode?> removeKid(int index) async {
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
        kidsArray.removeAt(index);
        if (kidsArray.isEmpty()) {
          pdfRepresentation().remove(PdfName.k);
        }
      }
    } else {
      removedKidObj = k;
      pdfRepresentation().remove(PdfName.k);
    }
    markChanged();
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
        pdfRepresentation().remove(PdfName.k);
      }
    } else {
      if (k == kid) {
        pdfRepresentation().remove(PdfName.k);
      }
    }
    markChanged();
  }

  /// Gets the parent of this structure element: either another element or the
  /// structure tree root.
  Future<StructureNode?> getParent() async {
    final parentObj = await pdfRepresentation().dictionaryEntry(PdfName.p);
    if (parentObj == null) return null;
    final type = await parentObj.nameEntry(PdfName.type);
    if (PdfName.structTreeRoot == type) {
      final root = PdfStructTreeRoot(parentObj);
      final document = getDocument();
      if (document != null) root.setDocument(document);
      return root;
    }
    if (await isStructElem(parentObj)) {
      return PdfStructElem(parentObj);
    }
    return null;
  }

  /// Points /P at [parent], which the specification requires to be an
  /// indirect reference.
  void setParent(PdfObject parent) {
    put(PdfName.p, parent.indirectHandle() ?? parent);
  }

  /// Gets list of the direct kids of structure element.
  Future<List<StructureNode>> getKids() async {
    final k = await getK();
    final kids = <StructureNode>[];
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

  Future<StructureNode> wrapKid(PdfObject kid) async {
    if (kid is PdfDictionary) {
      if (await isStructElem(kid)) {
        return PdfStructElem(kid);
      }
      final type = await kid.nameEntry(PdfName.type);
      if (TaggingNames.objr == type) {
        return PdfObjRef(kid, this);
      }
      final mcr = await PdfMcr.fromDictionary(kid, this);
      return mcr!;
    } else if (kid is PdfNumber) {
      return PdfMcr.fromObject(kid, this);
    }
    throw Exception('Unknown kid type: ${kid.runtimeType}');
  }

  /// Gets the K value (kids).
  Future<PdfObject?> getK() async {
    return await pdfRepresentation().get(PdfName.k, true);
  }

  /// Puts a value into the structure element dictionary.
  PdfStructElem put(PdfName key, PdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
    return this;
  }

  @override
  bool requiresIndirectStorage() => true;

  /// Internal method to add kid object to parent.
  Future<void> _addKidObject(
      PdfDictionary parent, int index, PdfObject kid) async {
    final k = await parent.get(PdfName.k, true);
    if (k == null) {
      if (index <= 0) {
        parent.put(PdfName.k, kid);
      } else {
        final a = PdfArray();
        a.add(kid);
        parent.put(PdfName.k, a);
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
      if (index < 0 || index >= a.size()) {
        a.add(kid);
      } else {
        a.insert(index, kid);
      }
    }
    parent.markChanged();
    if (kid is PdfDictionary && await PdfStructElem.isStructElem(kid)) {
      kid.put(PdfName.p, parent.indirectHandle() ?? parent);
      kid.markChanged();
    }
  }
}
