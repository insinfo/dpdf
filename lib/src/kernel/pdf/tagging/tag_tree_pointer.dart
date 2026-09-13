import '../pdf_document.dart';
import '../pdf_dictionary.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_page.dart';
import '../pdf_stream.dart';
import '../pdf_string.dart';
import '../pdf_name.dart';
import 'tag_structure_context.dart';
import 'pdf_mcr.dart';
import 'pdf_obj_ref.dart';
import 'pdf_struct_elem.dart';
import 'pdf_struct_tree_root.dart';
import 'pdf_namespace.dart';
import 'tagging_names.dart';

/// A cursor over the structure tree: it remembers where the next tag goes and
/// ties the page content being written to the element that owns it
/// (ISO 32000-1:2008, 14.7 and 14.8).
class TagTreePointer {
  final TagStructureContext tagStructureContext;
  PdfStructElem? _currentStructElem;
  PdfPage? _currentPage;
  PdfStream? _contentStream;
  PdfNamespace? _currentNamespace;
  int _nextNewKidIndex = -1;

  TagTreePointer(PdfDocument document)
      : tagStructureContext = document.taggingContext()! {
    _currentNamespace = tagStructureContext.getDocumentDefaultNamespace();
  }

  /// Creates a pointer already parked on the document's root tag.
  static Future<TagTreePointer> create(PdfDocument document) async {
    final pointer = TagTreePointer(document);
    await pointer.moveToRoot();
    return pointer;
  }

  TagTreePointer.copy(TagTreePointer other)
      : tagStructureContext = other.tagStructureContext,
        _currentStructElem = other._currentStructElem,
        _currentPage = other._currentPage,
        _contentStream = other._contentStream,
        _currentNamespace = other._currentNamespace;

  TagTreePointer.fromStructElem(this._currentStructElem, PdfDocument document)
      : tagStructureContext = document.taggingContext()!;

  TagTreePointer setPageForTagging(PdfPage page) {
    _currentPage = page;
    return this;
  }

  PdfPage? getCurrentPage() => _currentPage;

  TagTreePointer setContentStreamForTagging(PdfStream? contentStream) {
    _contentStream = contentStream;
    return this;
  }

  PdfStream? getCurrentContentStream() => _contentStream;

  TagStructureContext getContext() => tagStructureContext;

  PdfDocument getDocument() => tagStructureContext.getDocument();

  TagTreePointer setNamespaceForNewTags(PdfNamespace? namespace) {
    _currentNamespace = namespace;
    return this;
  }

  PdfNamespace? getNamespaceForNewTags() => _currentNamespace;

  PdfStructElem getCurrentStructElem() {
    if (_currentStructElem == null) {
      throw StateError('Current structure element is not initialized.');
    }
    return _currentStructElem!;
  }

  void setCurrentStructElem(PdfStructElem structElem) {
    _currentStructElem = structElem;
  }

  PdfStructTreeRoot _structTreeRoot() {
    final root = getDocument().structureRoot();
    root.setDocument(getDocument());
    return root;
  }

  // ------------------------------------------------------------ adding tags

  Future<TagTreePointer> addTag(String role) async {
    return addTagAt(-1, role);
  }

  Future<TagTreePointer> addTagAt(int index, String role) async {
    await tagStructureContext.checkRole(role, _currentNamespace);
    setNextNewKidIndex(index);
    final newKid = PdfStructElem.withRole(getDocument(), PdfName(role));
    if (_currentNamespace != null) {
      newKid.setNamespace(_currentNamespace!);
    }
    final current = getCurrentStructElem();
    final insertIndex = _getNextNewKidPosition();
    await current.addKid(newKid, insertIndex);
    setCurrentStructElem(newKid);
    return this;
  }

  TagTreePointer setNextNewKidIndex(int nextNewKidIndex) {
    if (nextNewKidIndex > -1) {
      _nextNewKidIndex = nextNewKidIndex;
    }
    return this;
  }

  int _getNextNewKidPosition() {
    final nextPos = _nextNewKidIndex;
    _nextNewKidIndex = -1;
    return nextPos;
  }

  // ------------------------------------------------------- content items

  /// Attaches the next marked-content sequence of the current page (or of the
  /// content stream set with [setContentStreamForTagging]) to the current tag
  /// and returns the reference that was created.
  ///
  /// The marked-content identifier it carries is the one that has to be
  /// written into the page as `/Tag << /MCID n >> BDC` (14.7.4.2).
  Future<PdfMcr> addMarkedContentReference() async {
    final page = _currentPage;
    if (page == null) {
      throw StateError('Tagging page content requires a page; call '
          'setPageForTagging first.');
    }
    final element = getCurrentStructElem();
    final root = _structTreeRoot();
    final owner = _contentStream ?? page.pdfRepresentation();

    if (!element.pdfRepresentation().containsKey(TaggingNames.pg)) {
      element.setPage(page);
    }
    final mcid = await root.getNextMcid(owner);

    final PdfMcr mcr;
    final elementPage = await element.getPageObject();
    if (_contentStream == null &&
        identical(elementPage, page.pdfRepresentation())) {
      mcr = PdfMcrNumber.withMcid(mcid, element);
    } else {
      mcr = PdfMcrDictionary.create(page, mcid,
          parent: element, stream: _contentStream);
    }
    await element.addMcr(mcr);
    await root.registerMarkedContent(owner, mcid, element);
    return mcr;
  }

  /// The property list a `BDC` operator needs for the marked-content sequence
  /// created by [addMarkedContentReference].
  Future<PdfDictionary> markedContentProperties(PdfMcr mcr) async {
    final properties = PdfDictionary();
    properties.put(TaggingNames.mcid, PdfNumber.fromInt(await mcr.getMcid()));
    return properties;
  }

  /// Makes the whole object [referenced] — an annotation, a form or image
  /// XObject — a content item of the current tag (14.7.4.3).
  Future<PdfObjRef> addObjectReference(PdfDictionary referenced) async {
    final element = getCurrentStructElem();
    final page = _currentPage;
    final objRef = PdfObjRef.create(referenced, element, page: page);
    await element.addObjRef(objRef);
    await _structTreeRoot().registerObjectReference(referenced, element);
    return objRef;
  }

  // ------------------------------------------------------------- navigation

  Future<TagTreePointer> moveToRoot() async {
    setCurrentStructElem(await tagStructureContext.getRootTag());
    return this;
  }

  Future<TagTreePointer> moveToParent() async {
    final current = getCurrentStructElem();
    final parent = await current.getParent();
    if (parent is PdfStructElem) {
      setCurrentStructElem(parent);
    } else {
      await moveToRoot();
    }
    return this;
  }

  Future<TagTreePointer> moveToKid(int kidIndex) async {
    final current = getCurrentStructElem();
    final kids = await current.getKids();
    if (kidIndex >= 0 && kidIndex < kids.length) {
      final kid = kids[kidIndex];
      if (kid is PdfStructElem) {
        setCurrentStructElem(kid);
      } else {
        throw Exception('Cannot move to non-element kid (MCR or flushed)');
      }
    }
    return this;
  }

  /// Moves to the first kid whose role is [role].
  Future<TagTreePointer> moveToKidWithRole(String role) async {
    final kids = await getCurrentStructElem().getKids();
    for (final kid in kids) {
      if (kid is! PdfStructElem) continue;
      if ((await kid.getRole())?.getValue() == role) {
        setCurrentStructElem(kid);
        return this;
      }
    }
    throw StateError('No kid of the current tag has the role /$role.');
  }

  Future<List<String?>> getKidsRoles() async {
    final current = getCurrentStructElem();
    final kids = await current.getKids();
    final roles = <String?>[];
    for (final kid in kids) {
      roles.add((await kid.getRole())?.getValue());
    }
    return roles;
  }

  /// Gets the role of the current tag.
  Future<String?> getRole() async {
    final role = await getCurrentStructElem().getRole();
    return role?.getValue();
  }

  /// Sets a new role to the current tag.
  Future<TagTreePointer> setRole(String role) async {
    await tagStructureContext.checkRole(role, _currentNamespace);
    getCurrentStructElem().setRole(PdfName(role));
    return this;
  }

  // ------------------------------------------------------- element payload

  TagTreePointer setTitle(String title) {
    getCurrentStructElem().setTitle(PdfString(title));
    return this;
  }

  TagTreePointer setLang(String lang) {
    getCurrentStructElem().setLang(PdfString(lang));
    return this;
  }

  TagTreePointer setAlt(String alt) {
    getCurrentStructElem().setAlt(PdfString(alt));
    return this;
  }

  TagTreePointer setActualText(String actualText) {
    getCurrentStructElem().setActualText(PdfString(actualText));
    return this;
  }

  TagTreePointer setExpansion(String expansion) {
    getCurrentStructElem().setE(PdfString(expansion));
    return this;
  }

  /// Sets the element identifier of the current tag and records it in the
  /// structure tree root's /IDTree.
  Future<TagTreePointer> setStructureElementId(String id) async {
    await getCurrentStructElem().setStructureElementId(PdfString(id));
    return this;
  }

  /// Attaches an attribute object to the current tag (14.7.5).
  Future<TagTreePointer> addAttribute(PdfObject attributes,
      {int revision = 0}) async {
    await getCurrentStructElem().addAttribute(attributes, revision: revision);
    return this;
  }

  /// Attaches a named attribute class to the current tag, registering
  /// [attributes] in the structure tree root's /ClassMap (14.7.5.2).
  Future<TagTreePointer> addAttributeClass(String className,
      {PdfObject? attributes, int revision = 0}) async {
    final name = PdfName(className);
    if (attributes != null) {
      await _structTreeRoot().addAttributeClass(name, attributes);
    }
    await getCurrentStructElem().addAttributeClass(name, revision: revision);
    return this;
  }

  // ---------------------------------------------------------------- removal

  /// Deletes the selected tag and reparents its children to the containing
  /// tag. This moves the pointer to the parent of the removed tag.
  Future<TagTreePointer> removeTag() async {
    final currentElem = getCurrentStructElem();
    final parent = await currentElem.getParent();
    if (parent == null) {
      throw StateError('Cannot remove root tag');
    }

    final kids = await currentElem.getKids();
    final index = await _getIndexInParentKidsList(currentElem);

    if (parent is PdfStructElem && index >= 0) {
      await parent.removeKid(index);

      var insertIdx = index;
      for (final kid in kids) {
        if (kid is PdfStructElem) {
          await parent.addKid(kid, insertIdx);
          insertIdx++;
        }
      }

      setCurrentStructElem(parent);
    } else if (parent is PdfStructTreeRoot) {
      await parent.removeKid(currentElem);
      for (final kid in kids) {
        if (kid is PdfStructElem) {
          await parent.addKid(kid);
        }
      }
      await moveToRoot();
    } else {
      await moveToRoot();
    }

    return this;
  }

  /// Chooses the insertion position among the parent's children.
  /// Returns -1 if current tag is root, parent is flushed, or it wasn't
  /// possible to define index.
  Future<int> getIndexInParentKidsList() async {
    return await _getIndexInParentKidsList(getCurrentStructElem());
  }

  Future<int> _getIndexInParentKidsList(PdfStructElem elem) async {
    final parent = await elem.getParent();
    if (parent == null) return -1;

    if (parent is PdfStructElem) {
      final kids = await parent.getKids();
      for (int i = 0; i < kids.length; i++) {
        final kid = kids[i];
        if (kid is PdfStructElem &&
            identical(kid.pdfRepresentation(), elem.pdfRepresentation())) {
          return i;
        }
      }
    }
    return -1;
  }

  /// Checks if given structure element is flushed.
  bool isElementFlushed(PdfStructElem elem) {
    return elem.hasBeenWritten();
  }
}
