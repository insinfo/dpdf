import '../pdf_document.dart';
import '../pdf_page.dart';
import '../pdf_stream.dart';
import '../pdf_name.dart';
import 'tag_structure_context.dart';
import 'pdf_struct_elem.dart';
import 'pdf_namespace.dart';

class TagTreePointer {
  final TagStructureContext tagStructureContext;
  PdfStructElem? _currentStructElem;
  PdfPage? _currentPage;
  PdfStream? _contentStream;
  PdfNamespace? _currentNamespace;
  int _nextNewKidIndex = -1;

  TagTreePointer(PdfDocument document)
      : tagStructureContext = document.getTagStructureContext()! {
    _init(document);
  }

  Future<void> _init(PdfDocument document) async {
    _currentStructElem = await tagStructureContext.getRootTag();
    _currentNamespace = tagStructureContext.getDocumentDefaultNamespace();
  }

  TagTreePointer.copy(TagTreePointer other)
      : tagStructureContext = other.tagStructureContext,
        _currentStructElem = other._currentStructElem,
        _currentPage = other._currentPage,
        _contentStream = other._contentStream,
        _currentNamespace = other._currentNamespace;

  TagTreePointer.fromStructElem(this._currentStructElem, PdfDocument document)
      : tagStructureContext = document.getTagStructureContext()!;

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

  Future<TagTreePointer> addTag(String role) async {
    return addTagAt(-1, role);
  }

  Future<TagTreePointer> addTagAt(int index, String role) async {
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
  TagTreePointer setRole(String role) {
    getCurrentStructElem().setRole(PdfName(role));
    return this;
  }

  /// Removes the current tag. If it has kids, they will become kids of the current tag parent.
  /// This method call moves this TagTreePointer to the current tag parent.
  Future<TagTreePointer> removeTag() async {
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
    if (parent is PdfStructElem && index >= 0) {
      await parent.removeKid(index);
      
      // Reparent kids to parent at original index position
      var insertIdx = index;
      for (final kid in kids) {
        if (kid is PdfStructElem) {
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

  /// Defines index of the current tag in the parent's kids list.
  /// Returns -1 if current tag is root, parent is flushed, or it wasn't possible to define index.
  Future<int> getIndexInParentKidsList() async {
    return await _getIndexInParentKidsList(getCurrentStructElem());
  }

  Future<int> _getIndexInParentKidsList(PdfStructElem elem) async {
    final parent = await elem.getParent();
    if (parent == null) return -1;
    
    if (parent is PdfStructElem) {
      final kids = await parent.getKids();
      for (int i = 0; i < kids.length; i++) {
        if (kids[i] == elem) return i;
      }
    }
    return -1;
  }

  /// Checks if given structure element is flushed.
  bool isElementFlushed(PdfStructElem elem) {
    return elem.isFlushed();
  }
}
