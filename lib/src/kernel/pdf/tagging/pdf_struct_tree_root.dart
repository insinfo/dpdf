import 'dart:math';

import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_null.dart';
import '../pdf_number.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_document.dart';
import '../pdf_object.dart';
import '../pdf_array.dart';
import '../pdf_page.dart';
import '../pdf_string.dart';
import 'pdf_struct_elem.dart';
import 'pdf_mcr.dart';
import 'pdf_namespace.dart';
import 'structure_tree_copier.dart';
import 'tagging_names.dart';

/// The root of a document's logical structure
/// (ISO 32000-1:2008, 14.7.2, Table 322).
///
/// Besides holding the top-level structure elements in /K, the root owns the
/// three lookup structures the specification attaches to it: the /ParentTree
/// used to go from a content item back to its structure element (14.7.4.4),
/// the /IDTree that resolves element identifiers, and the /RoleMap and
/// /ClassMap dictionaries.
class PdfStructTreeRoot extends PdfObjectWrapper<PdfDictionary>
    implements StructureNode {
  /// Maximum number of entries a single number/name tree node holds before the
  /// tree is split into /Kids, mirroring [PdfNumTree].
  static const int _nodeSize = 40;

  PdfDocument? _document;
  Map<int, PdfObject>? _parentTreeEntries;
  Map<String, PdfObject>? _idTreeEntries;

  PdfStructTreeRoot(super.dictionary);

  PdfStructTreeRoot.withDocument(PdfDocument document)
      : super(PdfDictionary()) {
    _document = document;
    pdfRepresentation().put(PdfName.type, PdfName.structTreeRoot);
    pdfRepresentation().attachToDocument(document);
  }

  void setDocument(PdfDocument doc) {
    _document = doc;
  }

  @override
  PdfDocument? getDocument() => _document ?? super.getDocument();

  // --------------------------------------------------------------------- K

  Future<void> addKid(PdfStructElem structElem, [int index = -1]) async {
    final kids = await getKidsObject();
    if (index < 0 || index >= kids.size()) {
      kids.add(structElem.pdfRepresentation());
    } else {
      kids.insert(index, structElem.pdfRepresentation());
    }
    structElem.pdfRepresentation().put(
        PdfName.p, pdfRepresentation().indirectHandle() ?? pdfRepresentation());
    structElem.markChanged();
    markChanged();
  }

  /// Detaches [structElem] from the top level of the tree.
  Future<bool> removeKid(PdfStructElem structElem) async {
    final kids = await pdfRepresentation().arrayEntry(PdfName.k);
    if (kids == null) {
      final single = await pdfRepresentation().get(PdfName.k, true);
      if (single != null && identical(single, structElem.pdfRepresentation())) {
        pdfRepresentation().remove(PdfName.k);
        markChanged();
        return true;
      }
      return false;
    }
    for (var i = 0; i < kids.size(); i++) {
      final kid = await kids.get(i, true);
      if (identical(kid, structElem.pdfRepresentation())) {
        kids.removeAt(i);
        markChanged();
        return true;
      }
    }
    return false;
  }

  @override
  Future<PdfName?> getRole() async => null;

  Future<List<PdfObject>> getKids() async {
    final k = await pdfRepresentation().get(PdfName.k, true);
    if (k == null) return [];
    if (k is PdfArray) {
      final list = <PdfObject>[];
      for (int i = 0; i < k.size(); i++) {
        final kid = await k.get(i, true);
        if (kid != null) list.add(kid);
      }
      return list;
    }
    return [k];
  }

  /// The top-level structure elements, already wrapped.
  Future<List<PdfStructElem>> getKidElements() async {
    final elements = <PdfStructElem>[];
    for (final kid in await getKids()) {
      if (kid is PdfDictionary && await PdfStructElem.isStructElem(kid)) {
        elements.add(PdfStructElem(kid));
      }
    }
    return elements;
  }

  Future<PdfArray> getKidsObject() async {
    var k = await pdfRepresentation().arrayEntry(PdfName.k);
    if (k == null) {
      k = PdfArray();
      final kObj = await pdfRepresentation().get(PdfName.k, true);
      if (kObj != null) {
        k.add(kObj);
      }
      pdfRepresentation().put(PdfName.k, k);
      markChanged();
    }
    return k;
  }

  // --------------------------------------------------------- RoleMap/ClassMap

  Future<PdfDictionary> getRoleMap() async {
    var roleMap = await pdfRepresentation().dictionaryEntry(PdfName.roleMap);
    if (roleMap == null) {
      roleMap = PdfDictionary();
      pdfRepresentation().put(PdfName.roleMap, roleMap);
      markChanged();
    }
    return roleMap;
  }

  Future<void> addRoleMapping(String fromRole, String toRole) async {
    final roleMap = await getRoleMap();
    roleMap.put(PdfName(fromRole), PdfName(toRole));
    roleMap.markChanged();
    markChanged();
  }

  /// Follows the /RoleMap chain from [role] until it reaches a role that is
  /// not remapped, guarding against the circular chains 14.7.3 explicitly
  /// permits.
  Future<String> resolveRole(String role) async {
    final roleMap =
        await pdfRepresentation().dictionaryEntry(PdfName.roleMap);
    if (roleMap == null) return role;
    var current = role;
    final seen = <String>{current};
    while (true) {
      final mapped = await roleMap.nameEntry(PdfName(current));
      if (mapped == null) return current;
      final next = mapped.getValue();
      if (!seen.add(next)) return current;
      current = next;
    }
  }

  /// The /ClassMap dictionary, which binds attribute class names to attribute
  /// objects (14.7.5.2).
  Future<PdfDictionary> getClassMap() async {
    var classMap = await pdfRepresentation().dictionaryEntry(PdfName.classMap);
    if (classMap == null) {
      classMap = PdfDictionary();
      pdfRepresentation().put(PdfName.classMap, classMap);
      markChanged();
    }
    return classMap;
  }

  /// Registers [attributes] under the attribute class [className].
  Future<void> addAttributeClass(
      PdfName className, PdfObject attributes) async {
    final classMap = await getClassMap();
    classMap.put(className, attributes);
    classMap.markChanged();
    markChanged();
  }

  /// Resolves an attribute class name through the /ClassMap.
  Future<PdfObject?> getAttributeClass(PdfName className) async {
    final classMap = await pdfRepresentation().dictionaryEntry(PdfName.classMap);
    if (classMap == null) return null;
    return await classMap.get(className, true);
  }

  // ------------------------------------------------------------- Namespaces

  Future<List<PdfNamespace>> getNamespaces() async {
    final namespacesArray =
        await pdfRepresentation().arrayEntry(PdfName.namespaces);
    if (namespacesArray == null) return [];

    final namespacesList = <PdfNamespace>[];
    for (int i = 0; i < namespacesArray.size(); i++) {
      final nsDict = await namespacesArray.dictionaryEntry(i);
      if (nsDict != null) {
        namespacesList.add(PdfNamespace(nsDict));
      }
    }
    return namespacesList;
  }

  Future<void> addNamespace(PdfNamespace namespace) async {
    final namespacesArray = await getNamespacesObject();
    final document = getDocument();
    if (document != null) {
      namespace.pdfRepresentation().attachToDocument(document);
    }
    namespacesArray.add(namespace.pdfRepresentation());
    namespacesArray.markChanged();
    markChanged();
  }

  /// Finds an already declared namespace by its /NS name.
  Future<PdfNamespace?> findNamespace(String namespaceName) async {
    for (final namespace in await getNamespaces()) {
      if (await namespace.getNamespaceName() == namespaceName) {
        return namespace;
      }
    }
    return null;
  }

  Future<PdfArray> getNamespacesObject() async {
    var namespacesArray =
        await pdfRepresentation().arrayEntry(PdfName.namespaces);
    if (namespacesArray == null) {
      namespacesArray = PdfArray();
      pdfRepresentation().put(PdfName.namespaces, namespacesArray);
      markChanged();
    }
    return namespacesArray;
  }

  // ------------------------------------------------------------- ParentTree

  /// Every entry of the structural parent tree, keyed by /StructParent(s).
  Future<Map<int, PdfObject>> getParentTreeEntries() async {
    if (_parentTreeEntries != null) return _parentTreeEntries!;
    final entries = <int, PdfObject>{};
    final treeRoot =
        await pdfRepresentation().dictionaryEntry(PdfName.parentTree);
    if (treeRoot != null) {
      await _readNumberTree(treeRoot, entries, <PdfDictionary>{});
    }
    _parentTreeEntries = entries;
    return entries;
  }

  Future<void> _readNumberTree(PdfDictionary node, Map<int, PdfObject> into,
      Set<PdfDictionary> seen) async {
    if (!seen.add(node)) return;
    final nums = await node.arrayEntry(TaggingNames.nums);
    if (nums != null) {
      for (var i = 0; i + 1 < nums.size(); i += 2) {
        final key = await nums.numberEntry(i);
        final value = await nums.get(i + 1, true);
        if (key != null && value != null) {
          into[key.intValue()] = value;
        }
      }
      return;
    }
    final kids = await node.arrayEntry(TaggingNames.kids);
    if (kids == null) return;
    for (var i = 0; i < kids.size(); i++) {
      final kid = await kids.dictionaryEntry(i);
      if (kid != null) await _readNumberTree(kid, into, seen);
    }
  }

  Future<PdfObject?> getParentTreeEntry(int key) async {
    return (await getParentTreeEntries())[key];
  }

  /// Stores [value] under [key] and rewrites the serialized /ParentTree.
  Future<void> putParentTreeEntry(int key, PdfObject value) async {
    final entries = await getParentTreeEntries();
    entries[key] = value;
    await _writeParentTree();
    final next = await getParentTreeNextKey();
    if (next <= key) {
      setParentTreeNextKey(key + 1);
    }
  }

  Future<void> _writeParentTree() async {
    final entries = await getParentTreeEntries();
    final keys = entries.keys.toList()..sort();
    final document = getDocument();
    PdfDictionary tree;
    if (keys.length <= _nodeSize) {
      tree = PdfDictionary();
      tree.put(TaggingNames.nums, _numsArrayFor(keys, 0, keys.length, entries));
    } else {
      final kids = PdfArray();
      for (var offset = 0; offset < keys.length; offset += _nodeSize) {
        final end = min(offset + _nodeSize, keys.length);
        final leaf = PdfDictionary();
        final limits = PdfArray();
        limits.add(PdfNumber.fromInt(keys[offset]));
        limits.add(PdfNumber.fromInt(keys[end - 1]));
        leaf.put(TaggingNames.limits, limits);
        leaf.put(
            TaggingNames.nums, _numsArrayFor(keys, offset, end, entries));
        if (document != null) leaf.attachToDocument(document);
        kids.add(leaf);
      }
      tree = PdfDictionary();
      tree.put(TaggingNames.kids, kids);
    }
    if (document != null) tree.attachToDocument(document);
    pdfRepresentation().put(PdfName.parentTree, tree);
    markChanged();
  }

  PdfArray _numsArrayFor(
      List<int> keys, int from, int to, Map<int, PdfObject> entries) {
    final nums = PdfArray();
    for (var i = from; i < to; i++) {
      nums.add(PdfNumber.fromInt(keys[i]));
      final value = entries[keys[i]]!;
      nums.add(value.indirectHandle() ?? value);
    }
    return nums;
  }

  /// The value 14.7.4.4 requires to be greater than any key currently in the
  /// parent tree.
  Future<int> getParentTreeNextKey() async {
    final nextKeyObj =
        await pdfRepresentation().numberEntry(PdfName.parentTreeNextKey);
    if (nextKeyObj != null) {
      return nextKeyObj.intValue();
    }
    final entries = await getParentTreeEntries();
    if (entries.isEmpty) return 0;
    var maxKey = -1;
    for (final key in entries.keys) {
      if (key > maxKey) maxKey = key;
    }
    return maxKey + 1;
  }

  void setParentTreeNextKey(int value) {
    pdfRepresentation().put(PdfName.parentTreeNextKey, PdfNumber.fromInt(value));
    markChanged();
  }

  /// Takes the current /ParentTreeNextKey and advances it, as 14.7.4.4
  /// prescribes for every new parent tree entry.
  Future<int> allocateParentTreeKey() async {
    final key = await getParentTreeNextKey();
    setParentTreeNextKey(key + 1);
    return key;
  }

  // -------------------------------------------------------- content items

  /// Makes sure [contentOwner] (a page object or another content stream
  /// dictionary) carries a /StructParents key and returns it.
  Future<int> ensureStructParents(PdfDictionary contentOwner) async {
    final existing =
        (await contentOwner.numberEntry(PdfName.structParents))?.intValue();
    if (existing != null) return existing;
    final key = await allocateParentTreeKey();
    contentOwner.put(PdfName.structParents, PdfNumber.fromInt(key));
    contentOwner.markChanged();
    final array = PdfArray();
    final document = getDocument();
    if (document != null) array.attachToDocument(document);
    await putParentTreeEntry(key, array);
    return key;
  }

  /// Records that the marked-content sequence [mcid] inside [contentOwner]
  /// belongs to [parent] (14.7.4.4).
  Future<void> registerMarkedContent(
      PdfDictionary contentOwner, int mcid, PdfStructElem parent) async {
    if (mcid < 0) {
      throw ArgumentError.value(
          mcid, 'mcid', 'A marked-content identifier cannot be negative.');
    }
    final key = await ensureStructParents(contentOwner);
    var entry = await getParentTreeEntry(key);
    if (entry is! PdfArray) {
      entry = PdfArray();
      final document = getDocument();
      if (document != null) entry.attachToDocument(document);
      await putParentTreeEntry(key, entry);
    }
    final array = entry;
    while (array.size() <= mcid) {
      array.add(PdfNull());
    }
    final parentObject = parent.pdfRepresentation();
    array.set(mcid, parentObject.indirectHandle() ?? parentObject);
    array.markChanged();
    markChanged();
  }

  /// Records that the whole object [referenced] is a content item of [parent],
  /// allocating its /StructParent key when needed (14.7.4.3 and 14.7.4.4).
  Future<int> registerObjectReference(
      PdfDictionary referenced, PdfStructElem parent) async {
    var key =
        (await referenced.numberEntry(PdfName.structParent))?.intValue();
    if (key == null) {
      key = await allocateParentTreeKey();
      referenced.put(PdfName.structParent, PdfNumber.fromInt(key));
      referenced.markChanged();
    }
    await putParentTreeEntry(key, parent.pdfRepresentation());
    return key;
  }

  /// The marked-content references of [page], rebuilt from the parent tree.
  ///
  /// The parent tree stores the *parent structure element* of every
  /// marked-content identifier, so each array slot is turned back into a
  /// [PdfMcrNumber] carrying that index.
  Future<List<PdfMcr>?> getPageMarkedContentReferences(PdfPage page) async {
    final structParents = await page.getStructParents();
    if (structParents == null) return null;

    final entry = await getParentTreeEntry(structParents);
    if (entry == null) return null;

    final mcrs = <PdfMcr>[];
    if (entry is PdfArray) {
      for (int i = 0; i < entry.size(); i++) {
        final parentObj = await entry.get(i, true);
        if (parentObj is! PdfDictionary) continue;
        if (!await PdfStructElem.isStructElem(parentObj)) continue;
        mcrs.add(PdfMcrNumber.withMcid(i, PdfStructElem(parentObj)));
      }
    }
    return mcrs.isEmpty ? null : mcrs;
  }

  /// The first marked-content identifier still free on [page].
  Future<int> getNextMcidForPage(PdfPage page) async {
    return await getNextMcid(page.pdfRepresentation());
  }

  /// The first marked-content identifier still free in [contentOwner], which
  /// is a page object or another content stream dictionary.
  ///
  /// Identifiers index the parent tree array of the owner, so the next free
  /// one is simply the current length of that array (14.7.4.4).
  Future<int> getNextMcid(PdfDictionary contentOwner) async {
    final key =
        (await contentOwner.numberEntry(PdfName.structParents))?.intValue();
    if (key == null) return 0;
    final entry = await getParentTreeEntry(key);
    if (entry is PdfArray) return entry.size();
    return 0;
  }

  // ----------------------------------------------------------------- IDTree

  /// Every /IDTree entry, keyed by element identifier.
  Future<Map<String, PdfObject>> getElementIds() async {
    if (_idTreeEntries != null) return _idTreeEntries!;
    final entries = <String, PdfObject>{};
    final treeRoot = await pdfRepresentation().dictionaryEntry(PdfName.idTree);
    if (treeRoot != null) {
      await _readNameTree(treeRoot, entries, <PdfDictionary>{});
    }
    _idTreeEntries = entries;
    return entries;
  }

  Future<void> _readNameTree(PdfDictionary node, Map<String, PdfObject> into,
      Set<PdfDictionary> seen) async {
    if (!seen.add(node)) return;
    final names = await node.arrayEntry(TaggingNames.names);
    if (names != null) {
      for (var i = 0; i + 1 < names.size(); i += 2) {
        final key = await names.stringEntry(i);
        final value = await names.get(i + 1, true);
        if (key != null && value != null) {
          into[key.getValue()] = value;
        }
      }
      return;
    }
    final kids = await node.arrayEntry(TaggingNames.kids);
    if (kids == null) return;
    for (var i = 0; i < kids.size(); i++) {
      final kid = await kids.dictionaryEntry(i);
      if (kid != null) await _readNameTree(kid, into, seen);
    }
  }

  /// Binds the element identifier [id] to [element] in the /IDTree.
  Future<void> registerElementId(PdfString id, PdfStructElem element) async {
    final entries = await getElementIds();
    entries[id.getValue()] = element.pdfRepresentation();
    await _writeIdTree();
  }

  /// Drops the /IDTree entry for [id].
  Future<bool> removeElementId(PdfString id) async {
    final entries = await getElementIds();
    final removed = entries.remove(id.getValue()) != null;
    if (removed) await _writeIdTree();
    return removed;
  }

  /// Resolves an element identifier to its structure element.
  Future<PdfStructElem?> getElementById(PdfString id) async {
    final entry = (await getElementIds())[id.getValue()];
    if (entry is PdfDictionary) return PdfStructElem(entry);
    return null;
  }

  Future<void> _writeIdTree() async {
    final entries = await getElementIds();
    if (entries.isEmpty) {
      pdfRepresentation().remove(PdfName.idTree);
      markChanged();
      return;
    }
    final keys = entries.keys.toList()..sort();
    final document = getDocument();
    PdfDictionary tree;
    if (keys.length <= _nodeSize) {
      tree = PdfDictionary();
      tree.put(TaggingNames.names, _namesArrayFor(keys, 0, keys.length, entries));
    } else {
      final kids = PdfArray();
      for (var offset = 0; offset < keys.length; offset += _nodeSize) {
        final end = min(offset + _nodeSize, keys.length);
        final leaf = PdfDictionary();
        final limits = PdfArray();
        limits.add(PdfString(keys[offset]));
        limits.add(PdfString(keys[end - 1]));
        leaf.put(TaggingNames.limits, limits);
        leaf.put(
            TaggingNames.names, _namesArrayFor(keys, offset, end, entries));
        if (document != null) leaf.attachToDocument(document);
        kids.add(leaf);
      }
      tree = PdfDictionary();
      tree.put(TaggingNames.kids, kids);
    }
    if (document != null) tree.attachToDocument(document);
    pdfRepresentation().put(PdfName.idTree, tree);
    markChanged();
  }

  PdfArray _namesArrayFor(
      List<String> keys, int from, int to, Map<String, PdfObject> entries) {
    final names = PdfArray();
    for (var i = from; i < to; i++) {
      names.add(PdfString(keys[i]));
      final value = entries[keys[i]]!;
      names.add(value.indirectHandle() ?? value);
    }
    return names;
  }

  // ------------------------------------------------------------------- move

  /// Reorders the top-level structure so the elements whose content lives on
  /// [page] precede the elements belonging to the page currently numbered
  /// [insertBefore] (1-based).
  ///
  /// This keeps the reading order of the structure tree in step with a page
  /// that was relocated inside the same document. Structure elements that
  /// straddle several pages are left where they are, because moving them
  /// would change the reading order of pages that did not move.
  Future<void> move(PdfPage page, int insertBefore) async {
    final document = getDocument();
    if (document == null) return;
    if (insertBefore < 1 || insertBefore > document.pageTotal() + 1) {
      throw RangeError.range(
          insertBefore, 1, document.pageTotal() + 1, 'insertBefore');
    }
    final destination = insertBefore <= document.pageTotal()
        ? await document.pageAt(insertBefore)
        : null;

    final container = await _reorderContainer();
    if (container == null) return;
    final kids = container.kids;
    if (kids.size() < 2) return;

    final raw = kids.toListCopy();
    final moved = <PdfObject>[];
    final kept = <PdfObject>[];
    for (var i = 0; i < raw.length; i++) {
      final resolved = await kids.get(i, true);
      final pages = resolved is PdfDictionary
          ? await _pagesOf(resolved, <PdfDictionary>{})
          : const <PdfDictionary>{};
      if (pages.length == 1 && pages.contains(page.pdfRepresentation())) {
        moved.add(raw[i]);
      } else {
        kept.add(raw[i]);
      }
    }
    if (moved.isEmpty || kept.isEmpty) return;

    var target = kept.length;
    if (destination != null) {
      for (var i = 0; i < kept.length; i++) {
        final resolved = kept[i] is PdfIndirectReference
            ? await (kept[i] as PdfIndirectReference).targetObject(true)
            : kept[i];
        if (resolved is! PdfDictionary) continue;
        final pages = await _pagesOf(resolved, <PdfDictionary>{});
        if (pages.contains(destination.pdfRepresentation())) {
          target = i;
          break;
        }
      }
    }

    kids.clear();
    kids.addAll(kept.sublist(0, target));
    kids.addAll(moved);
    kids.addAll(kept.sublist(target));
    kids.markChanged();
    container.owner.markChanged();
    markChanged();
  }

  Future<_ReorderContainer?> _reorderContainer() async {
    final topLevel = await getKidElements();
    if (topLevel.length == 1) {
      final only = topLevel.first;
      final k = await only.getK();
      if (k is PdfArray) {
        return _ReorderContainer(only.pdfRepresentation(), k);
      }
      return null;
    }
    final kids = await pdfRepresentation().arrayEntry(PdfName.k);
    if (kids == null) return null;
    return _ReorderContainer(pdfRepresentation(), kids);
  }

  Future<Set<PdfDictionary>> _pagesOf(
      PdfDictionary element, Set<PdfDictionary> seen) async {
    final pages = <PdfDictionary>{};
    if (!seen.add(element)) return pages;
    final page = await element.dictionaryEntry(TaggingNames.pg);
    if (page != null) pages.add(page);
    final k = await element.get(PdfName.k, true);
    if (k == null) return pages;
    final items = <PdfObject>[];
    if (k is PdfArray) {
      for (var i = 0; i < k.size(); i++) {
        final item = await k.get(i, true);
        if (item != null) items.add(item);
      }
    } else {
      items.add(k);
    }
    for (final item in items) {
      if (item is PdfDictionary) {
        if (await PdfStructElem.isStructElem(item)) {
          pages.addAll(await _pagesOf(item, seen));
        } else {
          final itemPage = await item.dictionaryEntry(TaggingNames.pg);
          if (itemPage != null) pages.add(itemPage);
        }
      }
    }
    return pages;
  }

  // ------------------------------------------------------------------- copy

  /// Copies the structure that belongs to the pages of [pageMapping] into
  /// [destination] (14.7.2).
  ///
  /// See [StructureTreeCopier.copyStructure] for the details.
  Future<StructureCopyReport> copyTo(
      PdfDocument destination, Map<PdfPage, PdfPage> pageMapping,
      {Map<PdfObject, PdfObject> objectMapping = const {}}) async {
    final source = getDocument();
    if (source == null) {
      throw StateError('The structure tree root is not attached to a '
          'document, so it cannot be copied.');
    }
    return await StructureTreeCopier.copyStructure(
        source, destination, pageMapping,
        objectMapping: objectMapping);
  }

  @override
  bool requiresIndirectStorage() => true;
}

class _ReorderContainer {
  final PdfDictionary owner;
  final PdfArray kids;

  _ReorderContainer(this.owner, this.kids);
}
