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
class PdfNamespace extends PdfObjectWrapper<PdfDictionary> {
  PdfNamespace(PdfDictionary dictionary) : super(dictionary);

  PdfNamespace.fromName(String namespaceName)
      : this.fromPdfString(PdfString(namespaceName));

  PdfNamespace.fromPdfString(PdfString namespaceName) : super(PdfDictionary()) {
    put(PdfName.type, PdfName.namespace);
    put(PdfName.ns, namespaceName);
  }

  static Future<PdfNamespace> getDefault(PdfDocument pdfDocument) async {
    // TODO: implement getNamespaces and addNamespace in PdfStructTreeRoot
    return PdfNamespace.fromName(StandardNamespaces.pdf17);
  }

  PdfNamespace setNamespaceName(String namespaceName) {
    return setNamespaceNameString(PdfString(namespaceName));
  }

  PdfNamespace setNamespaceNameString(PdfString namespaceName) {
    return put(PdfName.ns, namespaceName);
  }

  Future<String?> getNamespaceName() async {
    final ns = await pdfRepresentation().stringEntry(PdfName.ns);
    return ns?.decodeMappingText();
  }

  PdfNamespace setSchema(PdfFileSpec fileSpec) {
    return put(PdfName.schema, fileSpec.pdfRepresentation());
  }

  Future<PdfFileSpec?> getSchema() async {
    final schemaObject = await pdfRepresentation().get(PdfName.schema);
    if (schemaObject is PdfDictionary) {
      return PdfFileSpec(schemaObject);
    }
    return null;
  }

  PdfNamespace setNamespaceRoleMap(PdfDictionary roleMapNs) {
    return put(PdfName.roleMapNS, roleMapNs);
  }

  Future<PdfDictionary?> getNamespaceRoleMap(
      [bool createIfNotExist = false]) async {
    var roleMapNs =
        await pdfRepresentation().dictionaryEntry(PdfName.roleMapNS);
    if (createIfNotExist && roleMapNs == null) {
      roleMapNs = PdfDictionary();
      put(PdfName.roleMapNS, roleMapNs);
    }
    return roleMapNs;
  }

  Future<PdfNamespace> addNamespaceRoleMapping(
      String thisNsRole, String defaultNsRole) async {
    final roleMap = await getNamespaceRoleMap(true);
    roleMap!.put(PdfName(thisNsRole), PdfName(defaultNsRole));
    markChanged();
    return this;
  }

  Future<PdfNamespace> addNamespaceRoleMappingWithTarget(
      String thisNsRole, String targetNsRole, PdfNamespace targetNs) async {
    final targetMapping = PdfArray();
    targetMapping.add(PdfName(targetNsRole));
    targetMapping.add(targetNs.pdfRepresentation());
    final roleMap = await getNamespaceRoleMap(true);
    roleMap!.put(PdfName(thisNsRole), targetMapping);
    markChanged();
    return this;
  }

  @override
  bool requiresIndirectStorage() => true;

  PdfNamespace put(PdfName key, PdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
    return this;
  }
}
