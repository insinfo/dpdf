import '../pdf_document.dart';
import '../pdf_page.dart';
import '../pdf_stream.dart';
import '../pdf_name.dart';
import 'tag_structure_context.dart';
import 'pdf_struct_elem.dart';
import 'pdf_namespace.dart';

class CraftTagTreePointer {
  final CraftTagStructureContext tagStructureContext;
  CraftPdfStructElem? _currentStructElem;
  CraftPdfPage? _currentPage;
  CraftPdfStream? _contentStream;
  CraftPdfNamespace? _currentNamespace;
  int _nextNewKidIndex = -1;

  CraftTagTreePointer(CraftPdfDocument document)
      : tagStructureContext = document.taggingContext()! {
    _init(document);
  }

  Future<void> _init(CraftPdfDocument document) async {
    _currentStructElem = await tagStructureContext.getRootTag();
    _currentNamespace = tagStructureContext.getDocumentDefaultNamespace();
  }

  CraftTagTreePointer.copy(CraftTagTreePointer other)
      : tagStructureContext = other.tagStructureContext,
        _currentStructElem = other._currentStructElem,
        _currentPage = other._currentPage,
        _contentStream = other._contentStream,
        _currentNamespace = other._currentNamespace;

  CraftTagTreePointer.fromStructElem(
      this._currentStructElem, CraftPdfDocument document)
      : tagStructureContext = document.taggingContext()!;

  CraftTagTreePointer setPageForTagging(CraftPdfPage page) {
    _currentPage = page;
    return this;
  }

  CraftPdfPage? getCurrentPage() => _currentPage;

  CraftTagTreePointer setContentStreamForTagging(
      CraftPdfStream? contentStream) {
    _contentStream = contentStream;
    return this;
  }

  CraftPdfStream? getCurrentContentStream() => _contentStream;

  CraftTagStructureContext getContext() => tagStructureContext;

  CraftPdfDocument getDocument() => tagStructureContext.getDocument();

  CraftTagTreePointer setNamespaceForNewTags(CraftPdfNamespace? namespace) {
    _currentNamespace = namespace;
    return this;
  }

  CraftPdfNamespace? getNamespaceForNewTags() => _currentNamespace;

  CraftPdfStructElem getCurrentStructElem() {
    if (_currentStructElem == null) {
      throw StateError('Current structure element is not initialized.');
    }
    return _currentStructElem!;
  }

  void setCurrentStructElem(CraftPdfStructElem structElem) {
    _currentStructElem = structElem;
  }

  Future<CraftTagTreePointer> addTag(String role) async {
    return addTagAt(-1, role);
  }

  Future<CraftTagTreePointer> addTagAt(int index, String role) async {
    setNextNewKidIndex(index);
    final newKid =
        CraftPdfStructElem.withRole(getDocument(), CraftPdfName(role));
    if (_currentNamespace != null) {
      newKid.setNamespace(_currentNamespace!);
    }
    final current = getCurrentStructElem();
    final insertIndex = _getNextNewKidPosition();
    await current.addKid(newKid, insertIndex);
    setCurrentStructElem(newKid);
    return this;
  }

  CraftTagTreePointer setNextNewKidIndex(int nextNewKidIndex) {
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

  Future<CraftTagTreePointer> moveToRoot() async {
    setCurrentStructElem(await tagStructureContext.getRootTag());
    return this;
  }

  Future<CraftTagTreePointer> moveToParent() async {
    final current = getCurrentStructElem();
    final parent = await current.getParent();
    if (parent is CraftPdfStructElem) {
      setCurrentStructElem(parent);
    } else {
      await moveToRoot();
    }
    return this;
  }

  Future<CraftTagTreePointer> moveToKid(int kidIndex) async {
    final current = getCurrentStructElem();
    final kids = await current.getKids();
    if (kidIndex >= 0 && kidIndex < kids.length) {
      final kid = kids[kidIndex];
      if (kid is CraftPdfStructElem) {
        setCurrentStructElem(kid);
      } else {
        throw Exception('Cannot move to non-element kid (MCR or flushed)');
      }
    }
    return this;
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
  CraftTagTreePointer setRole(String role) {
    getCurrentStructElem().setRole(CraftPdfName(role));
    return this;
  }

  /// Deletes the selected tag and reparents its children to the containing tag.
  /// This method call moves this TagTreePointer to the current tag parent.
  Future<CraftTagTreePointer> removeTag() async {
    final currentElem = getCurrentStructElem();
    final parent = await currentElem.getParent();
    if (parent == null) {
      throw StateError('Cannot remove root tag');
    }

    // Get kids of current to reparent them
    final kids = await currentElem.getKids();

    // Get current index in parent
    final index = await _getIndexInParentKidsList(currentElem);

    // Remove current from parent
    if (parent is CraftPdfStructElem && index >= 0) {
      await parent.removeKid(index);

      // Reparent kids to parent at original index position
      var insertIdx = index;
      for (final kid in kids) {
        if (kid is CraftPdfStructElem) {
          await parent.addKid(kid, insertIdx);
          insertIdx++;
        }
      }

      setCurrentStructElem(parent);
    } else {
      await moveToRoot();
    }

    return this;
  }

  /// Chooses the insertion position among the parent's children.
  /// Returns -1 if current tag is root, parent is flushed, or it wasn't possible to define index.
  Future<int> getIndexInParentKidsList() async {
    return await _getIndexInParentKidsList(getCurrentStructElem());
  }

  Future<int> _getIndexInParentKidsList(CraftPdfStructElem elem) async {
    final parent = await elem.getParent();
    if (parent == null) return -1;

    if (parent is CraftPdfStructElem) {
      final kids = await parent.getKids();
      for (int i = 0; i < kids.length; i++) {
        if (kids[i] == elem) return i;
      }
    }
    return -1;
  }

  /// Checks if given structure element is flushed.
  bool isElementFlushed(CraftPdfStructElem elem) {
    return elem.hasBeenWritten();
  }
}
