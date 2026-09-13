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
  PdfNamespace(super.dictionary);

  PdfNamespace.fromName(String namespaceName)
      : this.fromPdfString(PdfString(namespaceName));

  PdfNamespace.fromPdfString(PdfString namespaceName) : super(PdfDictionary()) {
    put(PdfName.type, PdfName.namespace);
    put(PdfName.ns, namespaceName);
  }

  /// The document's default namespace, declared in the /Namespaces array of
  /// the structure tree root and reused across calls.
  ///
  /// PDF 2.0 requires every structure element to name a namespace; documents
  /// written against ISO 32000-1 use the PDF 1.7 standard structure namespace,
  /// which is what this returns.
  static Future<PdfNamespace> getDefault(PdfDocument pdfDocument) async {
    return await fetch(pdfDocument, StandardNamespaces.getDefault());
  }

  /// Returns the namespace named [namespaceName], declaring it in the
  /// structure tree root's /Namespaces array the first time it is asked for.
  static Future<PdfNamespace> fetch(
      PdfDocument pdfDocument, String namespaceName) async {
    final structTreeRoot = pdfDocument.structureRoot();
    structTreeRoot.setDocument(pdfDocument);
    final existing = await structTreeRoot.findNamespace(namespaceName);
    if (existing != null) return existing;
    final namespace = PdfNamespace.fromName(namespaceName);
    namespace.pdfRepresentation().attachToDocument(pdfDocument);
    await structTreeRoot.addNamespace(namespace);
    return namespace;
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

  /// The role [thisNsRole] maps to through /RoleMapNS, or null when this
  /// namespace does not remap it.
  ///
  /// The mapping value is either a single name, meaning the default namespace,
  /// or a two-element array naming the target role and the namespace it
  /// belongs to.
  Future<PdfName?> resolveNamespaceRole(String thisNsRole) async {
    final roleMap = await getNamespaceRoleMap();
    if (roleMap == null) return null;
    final mapping = await roleMap.get(PdfName(thisNsRole), true);
    if (mapping is PdfName) return mapping;
    if (mapping is PdfArray && mapping.size() > 0) {
      return await mapping.nameEntry(0);
    }
    return null;
  }

  /// The namespace the mapping of [thisNsRole] targets, when /RoleMapNS names
  /// one explicitly.
  Future<PdfNamespace?> resolveNamespaceRoleTarget(String thisNsRole) async {
    final roleMap = await getNamespaceRoleMap();
    if (roleMap == null) return null;
    final mapping = await roleMap.get(PdfName(thisNsRole), true);
    if (mapping is PdfArray && mapping.size() > 1) {
      final target = await mapping.dictionaryEntry(1);
      if (target != null) return PdfNamespace(target);
    }
    return null;
  }

  @override
  bool requiresIndirectStorage() => true;

  PdfNamespace put(PdfName key, PdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
    return this;
  }
}
