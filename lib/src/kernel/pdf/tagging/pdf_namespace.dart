import '../pdf_object_wrapper.dart';
import '../pdf_dictionary.dart';
import '../pdf_string.dart';
import '../pdf_name.dart';
import '../pdf_document.dart';
import '../pdf_object.dart';
import '../pdf_array.dart';
import '../filespec/pdf_file_spec.dart';
import 'standard_namespaces.dart';

/// A wrapper for namespace dictionaries (ISO 32000-2 section 14.7.4).
class CraftPdfNamespace extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  CraftPdfNamespace(CraftPdfDictionary dictionary) : super(dictionary);

  CraftPdfNamespace.fromName(String namespaceName)
      : this.fromPdfString(CraftPdfString(namespaceName));

  CraftPdfNamespace.fromPdfString(CraftPdfString namespaceName)
      : super(CraftPdfDictionary()) {
    put(CraftPdfName.type, CraftPdfName.namespace);
    put(CraftPdfName.ns, namespaceName);
  }

  static Future<CraftPdfNamespace> getDefault(
      CraftPdfDocument pdfDocument) async {
    // TODO: implement getNamespaces and addNamespace in PdfStructTreeRoot
    return CraftPdfNamespace.fromName(CraftStandardNamespaces.pdf17);
  }

  CraftPdfNamespace setNamespaceName(String namespaceName) {
    return setNamespaceNameString(CraftPdfString(namespaceName));
  }

  CraftPdfNamespace setNamespaceNameString(CraftPdfString namespaceName) {
    return put(CraftPdfName.ns, namespaceName);
  }

  Future<String?> getNamespaceName() async {
    final ns = await pdfRepresentation().stringEntry(CraftPdfName.ns);
    return ns?.decodeMappingText();
  }

  CraftPdfNamespace setSchema(CraftPdfFileSpec fileSpec) {
    return put(CraftPdfName.schema, fileSpec.pdfRepresentation());
  }

  Future<CraftPdfFileSpec?> getSchema() async {
    final schemaObject = await pdfRepresentation().get(CraftPdfName.schema);
    if (schemaObject is CraftPdfDictionary) {
      return CraftPdfFileSpec(schemaObject);
    }
    return null;
  }

  CraftPdfNamespace setNamespaceRoleMap(CraftPdfDictionary roleMapNs) {
    return put(CraftPdfName.roleMapNS, roleMapNs);
  }

  Future<CraftPdfDictionary?> getNamespaceRoleMap(
      [bool createIfNotExist = false]) async {
    var roleMapNs =
        await pdfRepresentation().dictionaryEntry(CraftPdfName.roleMapNS);
    if (createIfNotExist && roleMapNs == null) {
      roleMapNs = CraftPdfDictionary();
      put(CraftPdfName.roleMapNS, roleMapNs);
    }
    return roleMapNs;
  }

  Future<CraftPdfNamespace> addNamespaceRoleMapping(
      String thisNsRole, String defaultNsRole) async {
    final roleMap = await getNamespaceRoleMap(true);
    roleMap!.put(CraftPdfName(thisNsRole), CraftPdfName(defaultNsRole));
    markChanged();
    return this;
  }

  Future<CraftPdfNamespace> addNamespaceRoleMappingWithTarget(String thisNsRole,
      String targetNsRole, CraftPdfNamespace targetNs) async {
    final targetMapping = CraftPdfArray();
    targetMapping.add(CraftPdfName(targetNsRole));
    targetMapping.add(targetNs.pdfRepresentation());
    final roleMap = await getNamespaceRoleMap(true);
    roleMap!.put(CraftPdfName(thisNsRole), targetMapping);
    markChanged();
    return this;
  }

  @override
  bool requiresIndirectStorage() => true;

  CraftPdfNamespace put(CraftPdfName key, CraftPdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
    return this;
  }
}
