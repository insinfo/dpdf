import '../pdf_document.dart';
import '../pdf_page.dart';
import '../pdf_name.dart';
import '../pdf_dictionary.dart';
import 'pdf_struct_elem.dart';
import 'pdf_namespace.dart';
import 'standard_namespaces.dart';
import 'standard_roles.dart';
import 'waiting_tags_manager.dart';
import 'tag_tree_pointer.dart';

/// The document-wide state a tagging session needs: the root tag, the waiting
/// tags, the namespaces in play and the rules for accepting a role
/// (ISO 32000-1:2008, 14.7 and 14.8).
class TagStructureContext {
  final PdfDocument document;
  late final WaitingTagsManager waitingTagsManager;
  final Set<PdfDictionary> namespaces = {};
  final Map<String, PdfNamespace> nameToNamespace = {};
  TagTreePointer? autoTaggingPointer;
  PdfStructElem? rootTagElement;

  /// Whether a role that is neither standard nor mapped by /RoleMap should be
  /// rejected outright (14.8.4.1).
  bool forbidUnknownRoles = true;
  PdfNamespace? documentDefaultNamespace;

  TagStructureContext(this.document) {
    waitingTagsManager = WaitingTagsManager();
  }

  Future<TagTreePointer> getAutoTaggingPointer() async {
    autoTaggingPointer ??= await TagTreePointer.create(document);
    return autoTaggingPointer!;
  }

  WaitingTagsManager getWaitingTagsManager() => waitingTagsManager;

  PdfNamespace? getDocumentDefaultNamespace() => documentDefaultNamespace;

  void setDocumentDefaultNamespace(PdfNamespace? ns) {
    documentDefaultNamespace = ns;
    if (ns != null) {
      namespaces.add(ns.pdfRepresentation());
    }
  }

  /// Declares the PDF 1.7 standard structure namespace as the document
  /// default, registering it in the structure tree root.
  Future<PdfNamespace> useStandardNamespace(
      [String namespaceName = StandardNamespaces.pdf17]) async {
    final namespace = await PdfNamespace.fetch(document, namespaceName);
    nameToNamespace[namespaceName] = namespace;
    setDocumentDefaultNamespace(namespace);
    return namespace;
  }

  PdfNamespace fetchNamespace(String namespaceName) {
    var ns = nameToNamespace[namespaceName];
    if (ns == null) {
      ns = PdfNamespace.fromName(namespaceName);
      nameToNamespace[namespaceName] = ns;
      namespaces.add(ns.pdfRepresentation());
    }
    return ns;
  }

  Future<PdfStructElem> getRootTag() async {
    if (rootTagElement == null) {
      final structTreeRoot = document.structureRoot();
      structTreeRoot.setDocument(document);
      final kids = await structTreeRoot.getKids();
      if (kids.isNotEmpty && kids[0] is PdfDictionary) {
        rootTagElement = PdfStructElem(kids[0] as PdfDictionary);
      } else {
        // 14.8.4.2 asks for a single top-level element; Document is the type
        // for a complete document.
        rootTagElement =
            PdfStructElem.withRole(document, PdfName(StandardRoles.document));
        await structTreeRoot.addKid(rootTagElement!);
      }
    }
    return rootTagElement!;
  }

  /// Resolves [role] the way a conforming reader does: first through the
  /// namespace's /RoleMapNS, then through the structure tree root's /RoleMap
  /// (14.7.3).
  Future<String> resolveRole(String role, [PdfNamespace? namespace]) async {
    if (namespace != null) {
      final mapped = await namespace.resolveNamespaceRole(role);
      if (mapped != null) role = mapped.getValue();
    }
    final structTreeRoot = await document.loadStructureRoot();
    if (structTreeRoot == null) return role;
    return await structTreeRoot.resolveRole(role);
  }

  /// Whether [role] is usable as a structure type: either a standard type of
  /// [namespace], or a type the document's /RoleMap sends to a standard one.
  Future<bool> isRoleKnown(String role, [PdfNamespace? namespace]) async {
    final namespaceName = namespace == null
        ? StandardNamespaces.getDefault()
        : (await namespace.getNamespaceName() ??
            StandardNamespaces.getDefault());
    if (StandardNamespaces.roleBelongsToStandardNamespace(
        role, namespaceName)) {
      return true;
    }
    final resolved = await resolveRole(role, namespace);
    return StandardNamespaces.roleBelongsToStandardNamespace(
        resolved, namespaceName);
  }

  /// Throws when [role] cannot be understood and [forbidUnknownRoles] is set.
  Future<void> checkRole(String role, [PdfNamespace? namespace]) async {
    if (!forbidUnknownRoles) return;
    if (await isRoleKnown(role, namespace)) return;
    throw ArgumentError('The role /$role is neither a standard structure '
        'type nor mapped to one by /RoleMap.');
  }

  Future<TagStructureContext> removePageTags(PdfPage page) async {
    final structTreeRoot = document.structureRoot();
    structTreeRoot.setDocument(document);
    final pageMcrs = await structTreeRoot.getPageMarkedContentReferences(page);
    if (pageMcrs != null) {
      for (final mcr in pageMcrs) {
        final parent = mcr.parent;
        if (parent != null) {
          await parent.removeKidObject(mcr.pdfRepresentation());
        }
      }
    }
    return this;
  }

  Future<void> prepareToDocumentClosing() async {
    await waitingTagsManager.removeAllWaitingStates();
  }

  PdfDocument getDocument() => document;
}
