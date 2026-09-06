import '../pdf_document.dart';
import '../pdf_page.dart';
import '../pdf_name.dart';
import '../pdf_dictionary.dart';
import 'pdf_struct_elem.dart';
import 'pdf_namespace.dart';
import 'waiting_tags_manager.dart';
import 'tag_tree_pointer.dart';
import 'standard_roles.dart';

class CraftTagStructureContext {
  final CraftPdfDocument document;
  late final CraftWaitingTagsManager waitingTagsManager;
  final Set<CraftPdfDictionary> namespaces = {};
  final Map<String, CraftPdfNamespace> nameToNamespace = {};
  CraftTagTreePointer? autoTaggingPointer;
  CraftPdfStructElem? rootTagElement;
  bool forbidUnknownRoles = true;
  CraftPdfNamespace? documentDefaultNamespace;

  CraftTagStructureContext(this.document) {
    waitingTagsManager = CraftWaitingTagsManager();
  }

  Future<CraftTagTreePointer> getAutoTaggingPointer() async {
    if (autoTaggingPointer == null) {
      autoTaggingPointer = CraftTagTreePointer(document);
    }
    return autoTaggingPointer!;
  }

  CraftWaitingTagsManager getWaitingTagsManager() => waitingTagsManager;

  CraftPdfNamespace? getDocumentDefaultNamespace() => documentDefaultNamespace;

  void setDocumentDefaultNamespace(CraftPdfNamespace? ns) {
    documentDefaultNamespace = ns;
  }

  CraftPdfNamespace fetchNamespace(String namespaceName) {
    var ns = nameToNamespace[namespaceName];
    if (ns == null) {
      ns = CraftPdfNamespace.fromName(namespaceName);
      nameToNamespace[namespaceName] = ns;
    }
    return ns;
  }

  Future<CraftPdfStructElem> getRootTag() async {
    if (rootTagElement == null) {
      final structTreeRoot = document.structureRoot();
      final kids = await structTreeRoot.getKids();
      if (kids.isNotEmpty && kids[0] is CraftPdfDictionary) {
        rootTagElement = CraftPdfStructElem(kids[0] as CraftPdfDictionary);
      } else {
        // Create default root Document tag
        rootTagElement = CraftPdfStructElem.withRole(
            document, CraftPdfName(CraftStandardRoles.document));
        await structTreeRoot.addKid(rootTagElement!);
      }
    }
    return rootTagElement!;
  }

  Future<CraftTagStructureContext> removePageTags(CraftPdfPage page) async {
    final structTreeRoot = document.structureRoot();
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

  void prepareToDocumentClosing() {
    waitingTagsManager.removeAllWaitingStates();
  }

  CraftPdfDocument getDocument() => document;
}
