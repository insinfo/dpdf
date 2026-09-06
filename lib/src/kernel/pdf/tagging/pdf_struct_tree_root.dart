import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_document.dart';
import '../pdf_object.dart';
import '../pdf_array.dart';
import '../pdf_page.dart';
import 'pdf_struct_elem.dart';
import '../pdf_num_tree.dart';
import '../pdf_name_tree.dart';
import 'pdf_mcr.dart';
import 'pdf_namespace.dart';

class CraftPdfStructTreeRoot extends CraftPdfObjectWrapper<CraftPdfDictionary>
    implements CraftStructureNode {
  CraftPdfDocument? _document;

  CraftPdfStructTreeRoot(CraftPdfDictionary dictionary) : super(dictionary);

  CraftPdfStructTreeRoot.withDocument(CraftPdfDocument document)
      : super(CraftPdfDictionary()) {
    _document = document;
    pdfRepresentation().put(CraftPdfName.type, CraftPdfName.structTreeRoot);
    pdfRepresentation().attachToDocument(document);
  }

  void setDocument(CraftPdfDocument doc) {
    _document = doc;
  }

  CraftPdfDocument? getDocument() => _document;

  Future<void> addKid(CraftPdfStructElem structElem, [int index = -1]) async {
    final kids = await getKidsObject();
    if (index == -1) {
      kids.add(structElem.pdfRepresentation());
    } else {
      kids.insert(index, structElem.pdfRepresentation());
    }
    structElem.pdfRepresentation().put(CraftPdfName.p,
        pdfRepresentation().indirectHandle() ?? pdfRepresentation());
    markChanged();
  }

  @override
  Future<CraftPdfName?> getRole() async => null;

  Future<List<CraftPdfObject>> getKids() async {
    final k = await pdfRepresentation().get(CraftPdfName.k);
    if (k == null) return [];
    if (k is CraftPdfArray) {
      final list = <CraftPdfObject>[];
      for (int i = 0; i < k.size(); i++) {
        final kid = await k.get(i, true);
        if (kid != null) list.add(kid);
      }
      return list;
    }
    return [k];
  }

  Future<CraftPdfArray> getKidsObject() async {
    var k = await pdfRepresentation().arrayEntry(CraftPdfName.k);
    if (k == null) {
      k = CraftPdfArray();
      final kObj = await pdfRepresentation().get(CraftPdfName.k);
      if (kObj != null) {
        k.add(kObj);
      }
      pdfRepresentation().put(CraftPdfName.k, k);
      markChanged();
    }
    return k;
  }

  Future<CraftPdfDictionary> getRoleMap() async {
    var roleMap =
        await pdfRepresentation().dictionaryEntry(CraftPdfName.roleMap);
    if (roleMap == null) {
      roleMap = CraftPdfDictionary();
      pdfRepresentation().put(CraftPdfName.roleMap, roleMap);
      markChanged();
    }
    return roleMap;
  }

  Future<void> addRoleMapping(String fromRole, String toRole) async {
    final roleMap = await getRoleMap();
    roleMap.put(CraftPdfName(fromRole), CraftPdfName(toRole));
    markChanged();
  }

  Future<List<CraftPdfNamespace>> getNamespaces() async {
    final namespacesArray =
        await pdfRepresentation().arrayEntry(CraftPdfName.namespaces);
    if (namespacesArray == null) return [];

    final namespacesList = <CraftPdfNamespace>[];
    for (int i = 0; i < namespacesArray.size(); i++) {
      final nsDict = await namespacesArray.dictionaryEntry(i);
      if (nsDict != null) {
        namespacesList.add(CraftPdfNamespace(nsDict));
      }
    }
    return namespacesList;
  }

  Future<void> addNamespace(CraftPdfNamespace namespace) async {
    final namespacesArray = await getNamespacesObject();
    namespacesArray.add(namespace.pdfRepresentation());
    markChanged();
  }

  Future<CraftPdfArray> getNamespacesObject() async {
    var namespacesArray =
        await pdfRepresentation().arrayEntry(CraftPdfName.namespaces);
    if (namespacesArray == null) {
      namespacesArray = CraftPdfArray();
      pdfRepresentation().put(CraftPdfName.namespaces, namespacesArray);
      markChanged();
    }
    return namespacesArray;
  }

  Future<CraftPdfNumTree> getParentTree() async {
    final catalog = _document?.rootCatalog();
    if (catalog == null) throw StateError('Document or Catalog is null');
    return CraftPdfNumTree(catalog, CraftPdfName.parentTree);
  }

  Future<int> getParentTreeNextKey() async {
    final nextKeyObj =
        await pdfRepresentation().numberEntry(CraftPdfName.parentTreeNextKey);
    if (nextKeyObj != null) {
      return nextKeyObj.intValue();
    }
    final parentTree = await getParentTree();
    final numbers = await parentTree.getNumbers();
    if (numbers.isEmpty) return 0;
    int maxKey = -1;
    for (final key in numbers.keys) {
      if (key > maxKey) maxKey = key;
    }
    return maxKey + 1;
  }

  CraftPdfNameTree getIdTree() {
    if (_document == null) throw StateError('Document is null');
    return CraftPdfNameTree(_document!.rootCatalog(), CraftPdfName.idTree);
  }

  Future<List<CraftPdfMcr>?> getPageMarkedContentReferences(
      CraftPdfPage page) async {
    final structParents = await page.getStructParents();
    if (structParents == null) return null;

    final parentTree = await getParentTree();
    final parentObj = await parentTree.get(structParents);
    if (parentObj == null) return null;

    final mcrs = <CraftPdfMcr>[];
    if (parentObj is CraftPdfArray) {
      for (int i = 0; i < parentObj.size(); i++) {
        final kid = await parentObj.get(i, true);
        if (kid is CraftPdfDictionary) {
          final mcr = await CraftPdfMcr.fromDictionary(kid, null);
          if (mcr != null) mcrs.add(mcr);
        }
      }
    } else if (parentObj is CraftPdfDictionary) {
      final mcr = await CraftPdfMcr.fromDictionary(parentObj, null);
      if (mcr != null) mcrs.add(mcr);
    }
    return mcrs.isEmpty ? null : mcrs;
  }

  Future<int> getNextMcidForPage(CraftPdfPage page) async {
    final mcrs = await getPageMarkedContentReferences(page);
    if (mcrs == null || mcrs.isEmpty) {
      return 0;
    }
    int maxMcid = -1;
    for (final mcr in mcrs) {
      final mcid = await mcr.getMcid();
      if (mcid > maxMcid) {
        maxMcid = mcid;
      }
    }
    return maxMcid + 1;
  }

  Future<void> move(CraftPdfPage page, int insertBefore) async {
    // TODO: Implement structure tree move logic (StructureTreeCopier)
  }

  @override
  bool requiresIndirectStorage() => true;
}
