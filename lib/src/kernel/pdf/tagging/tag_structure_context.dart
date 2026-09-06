import '../pdf_document.dart';
import '../pdf_page.dart';
import '../pdf_name.dart';
import '../pdf_dictionary.dart';
import 'pdf_struct_elem.dart';
import 'pdf_namespace.dart';
import 'waiting_tags_manager.dart';
import 'tag_tree_pointer.dart';
import 'standard_roles.dart';

class TagStructureContext {
  final PdfDocument document;
  late final WaitingTagsManager waitingTagsManager;
  final Set<PdfDictionary> namespaces = {};
  final Map<String, PdfNamespace> nameToNamespace = {};
  TagTreePointer? autoTaggingPointer;
  PdfStructElem? rootTagElement;
  bool forbidUnknownRoles = true;
  PdfNamespace? documentDefaultNamespace;

  TagStructureContext(this.document) {
    waitingTagsManager = WaitingTagsManager();
  }

  Future<TagTreePointer> getAutoTaggingPointer() async {
    if (autoTaggingPointer == null) {
        autoTaggingPointer = TagTreePointer(document);
    }
    return autoTaggingPointer!;
  }

  WaitingTagsManager getWaitingTagsManager() => waitingTagsManager;

  PdfNamespace? getDocumentDefaultNamespace() => documentDefaultNamespace;

  void setDocumentDefaultNamespace(PdfNamespace? ns) {
    documentDefaultNamespace = ns;
  }

  PdfNamespace fetchNamespace(String namespaceName) {
    var ns = nameToNamespace[namespaceName];
    if (ns == null) {
      ns = PdfNamespace.fromName(namespaceName);
      nameToNamespace[namespaceName] = ns;
    }
    return ns;
  }

  Future<PdfStructElem> getRootTag() async {
    if (rootTagElement == null) {
      final structTreeRoot = document.getStructTreeRoot();
      final kids = await structTreeRoot.getKids();
      if (kids.isNotEmpty && kids[0] is PdfDictionary) {
        rootTagElement = PdfStructElem(kids[0] as PdfDictionary);
      } else {
        // Create default root Document tag
        rootTagElement = PdfStructElem.withRole(document, PdfName(StandardRoles.document));
        await structTreeRoot.addKid(rootTagElement!);
      }
    }
    return rootTagElement!;
  }

  Future<TagStructureContext> removePageTags(PdfPage page) async {
    final structTreeRoot = document.getStructTreeRoot();
    final pageMcrs = await structTreeRoot.getPageMarkedContentReferences(page);
    if (pageMcrs != null) {
      for (final mcr in pageMcrs) {
        final parent = mcr.parent;
        if (parent != null) {
            await parent.removeKidObject(mcr.getPdfObject());
        }
      }
    }
    return this;
  }

  void prepareToDocumentClosing() {
    waitingTagsManager.removeAllWaitingStates();
  }

  PdfDocument getDocument() => document;
}
