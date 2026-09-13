import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';
import 'tag_tree_pointer.dart';
import 'pdf_struct_elem.dart';

/// Keeps structure elements alive while the code that produced them is still
/// working on the page.
///
/// A tag is "waiting" while some object of the layout engine still owns it:
/// until that owner releases the tag, the element must not be written out,
/// because more children may still arrive. Once the waiting state is removed
/// and the element's parent has already been written, the element can never
/// change again and is flushed immediately.
class WaitingTagsManager {
  final Map<Object, PdfStructElem> _associatedObjToWaitingTag = {};
  final Map<PdfDictionary, Object> _waitingTagToAssociatedObj = {};

  WaitingTagsManager();

  Object? assignWaitingState(
      TagTreePointer pointerToTag, Object associatedObj) {
    return saveAssociatedObjectForWaitingTag(
        associatedObj, pointerToTag.getCurrentStructElem());
  }

  bool isObjectAssociatedWithWaitingTag(Object obj) {
    return _associatedObjToWaitingTag.containsKey(obj);
  }

  bool tryMovePointerToWaitingTag(
      TagTreePointer tagPointer, Object? associatedObject) {
    if (associatedObject == null) return false;
    final waitingStructElem = _associatedObjToWaitingTag[associatedObject];
    if (waitingStructElem != null) {
      tagPointer.setCurrentStructElem(waitingStructElem);
      return true;
    }
    return false;
  }

  /// Releases the waiting state of [associatedObject] and writes the tag out
  /// when its parent has already been written.
  Future<bool> removeWaitingState(Object? associatedObject) async {
    if (associatedObject == null) return false;
    final structElem = _associatedObjToWaitingTag.remove(associatedObject);
    if (structElem == null) return false;
    _waitingTagToAssociatedObj.remove(structElem.pdfRepresentation());
    await flushIfParentWasFlushed(structElem);
    return true;
  }

  /// Releases every waiting state, writing out the tags whose parent is gone.
  Future<void> removeAllWaitingStates() async {
    final waiting = _associatedObjToWaitingTag.values.toList();
    _associatedObjToWaitingTag.clear();
    _waitingTagToAssociatedObj.clear();
    for (final structElem in waiting) {
      await flushIfParentWasFlushed(structElem);
    }
  }

  PdfStructElem? getStructForObj(Object associatedObj) {
    return _associatedObjToWaitingTag[associatedObj];
  }

  Object? getObjForStructDict(PdfDictionary structDict) {
    return _waitingTagToAssociatedObj[structDict];
  }

  Object? saveAssociatedObjectForWaitingTag(
      Object associatedObj, PdfStructElem structElem) {
    _associatedObjToWaitingTag[associatedObj] = structElem;
    final prev = _waitingTagToAssociatedObj[structElem.pdfRepresentation()];
    _waitingTagToAssociatedObj[structElem.pdfRepresentation()] = associatedObj;
    return prev;
  }

  /// Writes [structElem] and its subtree when the parent it hangs from has
  /// already been written.
  ///
  /// A written parent can no longer record new children, so the element is
  /// final: holding it in memory only delays the inevitable. Elements whose
  /// parent is still open, or which are themselves still waiting through
  /// another owner, are left alone.
  Future<bool> flushIfParentWasFlushed(PdfStructElem structElem) async {
    if (structElem.hasBeenWritten()) return false;
    if (_waitingTagToAssociatedObj
        .containsKey(structElem.pdfRepresentation())) {
      return false;
    }
    final parent = await structElem.pdfRepresentation().get(PdfName.p, false);
    PdfObject? parentObject = parent;
    if (parentObject is PdfIndirectReference) {
      if (!parentObject.checkState(PdfObject.flushed)) return false;
    } else if (parentObject is PdfDictionary) {
      if (!parentObject.hasBeenWritten()) return false;
    } else {
      return false;
    }
    await _flushSubtree(structElem.pdfRepresentation(), <PdfDictionary>{});
    return true;
  }

  Future<void> _flushSubtree(
      PdfDictionary element, Set<PdfDictionary> seen) async {
    if (!seen.add(element)) return;
    final kids = await element.get(PdfName.k, true);
    final items = <PdfObject>[];
    if (kids is PdfArray) {
      for (var i = 0; i < kids.size(); i++) {
        final kid = await kids.get(i, true);
        if (kid != null) items.add(kid);
      }
    } else if (kids != null) {
      items.add(kids);
    }
    for (final item in items) {
      if (item is! PdfDictionary) continue;
      if (!await PdfStructElem.isStructElem(item)) continue;
      if (_waitingTagToAssociatedObj.containsKey(item)) continue;
      await _flushSubtree(item, seen);
    }
    element.clearState(PdfObject.forbidRelease);
    await element.flush();
  }
}
