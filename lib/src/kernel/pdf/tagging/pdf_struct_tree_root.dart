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

class PdfStructTreeRoot extends PdfObjectWrapper<PdfDictionary> implements IStructureNode {
  PdfDocument? _document;

  PdfStructTreeRoot(PdfDictionary dictionary) : super(dictionary);

  PdfStructTreeRoot.withDocument(PdfDocument document) : super(PdfDictionary()) {
    _document = document;
    getPdfObject().put(PdfName.type, PdfName.structTreeRoot);
    getPdfObject().makeIndirect(document);
  }

  void setDocument(PdfDocument doc) {
    _document = doc;
  }

  PdfDocument? getDocument() => _document;

  Future<void> addKid(PdfStructElem structElem, [int index = -1]) async {
    final kids = await getKidsObject();
    if (index == -1) {
      kids.add(structElem.getPdfObject());
    } else {
      kids.insert(index, structElem.getPdfObject());
    }
    structElem.getPdfObject().put(PdfName.p, getPdfObject().getIndirectReference() ?? getPdfObject());
    setModified();
  }

  @override
  Future<PdfName?> getRole() async => null;

  Future<List<PdfObject>> getKids() async {
    final k = await getPdfObject().get(PdfName.k);
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

  Future<PdfArray> getKidsObject() async {
    var k = await getPdfObject().getAsArray(PdfName.k);
    if (k == null) {
      k = PdfArray();
      final kObj = await getPdfObject().get(PdfName.k);
      if (kObj != null) {
        k.add(kObj);
      }
      getPdfObject().put(PdfName.k, k);
      setModified();
    }
    return k;
  }

  Future<PdfDictionary> getRoleMap() async {
    var roleMap = await getPdfObject().getAsDictionary(PdfName.roleMap);
    if (roleMap == null) {
      roleMap = PdfDictionary();
      getPdfObject().put(PdfName.roleMap, roleMap);
      setModified();
    }
    return roleMap;
  }

  Future<void> addRoleMapping(String fromRole, String toRole) async {
    final roleMap = await getRoleMap();
    roleMap.put(PdfName(fromRole), PdfName(toRole));
    setModified();
  }

  Future<List<PdfNamespace>> getNamespaces() async {
    final namespacesArray = await getPdfObject().getAsArray(PdfName.namespaces);
    if (namespacesArray == null) return [];
    
    final namespacesList = <PdfNamespace>[];
    for (int i = 0; i < namespacesArray.size(); i++) {
        final nsDict = await namespacesArray.getAsDictionary(i);
        if (nsDict != null) {
            namespacesList.add(PdfNamespace(nsDict));
        }
    }
    return namespacesList;
  }

  Future<void> addNamespace(PdfNamespace namespace) async {
    final namespacesArray = await getNamespacesObject();
    namespacesArray.add(namespace.getPdfObject());
    setModified();
  }

  Future<PdfArray> getNamespacesObject() async {
    var namespacesArray = await getPdfObject().getAsArray(PdfName.namespaces);
    if (namespacesArray == null) {
        namespacesArray = PdfArray();
        getPdfObject().put(PdfName.namespaces, namespacesArray);
        setModified();
    }
    return namespacesArray;
  }

  Future<PdfNumTree> getParentTree() async {
    final catalog = _document?.getCatalog();
    if (catalog == null) throw StateError('Document or Catalog is null');
    return PdfNumTree(catalog, PdfName.parentTree);
  }

  Future<int> getParentTreeNextKey() async {
    final nextKeyObj = await getPdfObject().getAsNumber(PdfName.parentTreeNextKey);
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

  PdfNameTree getIdTree() {
    if (_document == null) throw StateError('Document is null');
    return PdfNameTree(_document!.getCatalog(), PdfName.idTree);
  }

  Future<List<PdfMcr>?> getPageMarkedContentReferences(PdfPage page) async {
    final structParents = await page.getStructParents();
    if (structParents == null) return null;
    
    final parentTree = await getParentTree();
    final parentObj = await parentTree.get(structParents);
    if (parentObj == null) return null;
    
    final mcrs = <PdfMcr>[];
    if (parentObj is PdfArray) {
        for (int i = 0; i < parentObj.size(); i++) {
            final kid = await parentObj.get(i, true);
            if (kid is PdfDictionary) {
                final mcr = await PdfMcr.fromDictionary(kid, null);
                if (mcr != null) mcrs.add(mcr);
            }
        }
    } else if (parentObj is PdfDictionary) {
        final mcr = await PdfMcr.fromDictionary(parentObj, null);
        if (mcr != null) mcrs.add(mcr);
    }
    return mcrs.isEmpty ? null : mcrs;
  }

  Future<int> getNextMcidForPage(PdfPage page) async {
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

  Future<void> move(PdfPage page, int insertBefore) async {
     // TODO: Implement structure tree move logic (StructureTreeCopier)
  }

  @override
  bool isWrappedObjectMustBeIndirect() => true;
}
