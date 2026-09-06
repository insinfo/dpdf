import '../pdf_dictionary.dart';
import 'tag_tree_pointer.dart';
import 'pdf_struct_elem.dart';

class CraftWaitingTagsManager {
  final Map<Object, CraftPdfStructElem> _associatedObjToWaitingTag = {};
  final Map<CraftPdfDictionary, Object> _waitingTagToAssociatedObj = {};

  CraftWaitingTagsManager();

  Object? assignWaitingState(
      CraftTagTreePointer pointerToTag, Object associatedObj) {
    return saveAssociatedObjectForWaitingTag(
        associatedObj, pointerToTag.getCurrentStructElem());
  }

  bool isObjectAssociatedWithWaitingTag(Object obj) {
    return _associatedObjToWaitingTag.containsKey(obj);
  }

  bool tryMovePointerToWaitingTag(
      CraftTagTreePointer tagPointer, Object? associatedObject) {
    if (associatedObject == null) return false;
    final waitingStructElem = _associatedObjToWaitingTag[associatedObject];
    if (waitingStructElem != null) {
      tagPointer.setCurrentStructElem(waitingStructElem);
      return true;
    }
    return false;
  }

  bool removeWaitingState(Object? associatedObject) {
    if (associatedObject != null) {
      final structElem = _associatedObjToWaitingTag.remove(associatedObject);
      if (structElem != null) {
        _waitingTagToAssociatedObj.remove(structElem.pdfRepresentation());
        // TODO: Flush if parent is flushed
      }
      return structElem != null;
    }
    return false;
  }

  void removeAllWaitingStates() {
    _associatedObjToWaitingTag.clear();
    _waitingTagToAssociatedObj.clear();
  }

  CraftPdfStructElem? getStructForObj(Object associatedObj) {
    return _associatedObjToWaitingTag[associatedObj];
  }

  Object? getObjForStructDict(CraftPdfDictionary structDict) {
    return _waitingTagToAssociatedObj[structDict];
  }

  Object? saveAssociatedObjectForWaitingTag(
      Object associatedObj, CraftPdfStructElem structElem) {
    _associatedObjToWaitingTag[associatedObj] = structElem;
    final prev = _waitingTagToAssociatedObj[structElem.pdfRepresentation()];
    _waitingTagToAssociatedObj[structElem.pdfRepresentation()] = associatedObj;
    return prev;
  }
}
