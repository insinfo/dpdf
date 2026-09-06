import '../pdf_dictionary.dart';
import 'tag_tree_pointer.dart';
import 'pdf_struct_elem.dart';

class WaitingTagsManager {
  final Map<Object, PdfStructElem> _associatedObjToWaitingTag = {};
  final Map<PdfDictionary, Object> _waitingTagToAssociatedObj = {};

  WaitingTagsManager();

  Object? assignWaitingState(TagTreePointer pointerToTag, Object associatedObj) {
    return saveAssociatedObjectForWaitingTag(associatedObj, pointerToTag.getCurrentStructElem());
  }

  bool isObjectAssociatedWithWaitingTag(Object obj) {
    return _associatedObjToWaitingTag.containsKey(obj);
  }

  bool tryMovePointerToWaitingTag(TagTreePointer tagPointer, Object? associatedObject) {
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
        _waitingTagToAssociatedObj.remove(structElem.getPdfObject());
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

  PdfStructElem? getStructForObj(Object associatedObj) {
    return _associatedObjToWaitingTag[associatedObj];
  }

  Object? getObjForStructDict(PdfDictionary structDict) {
    return _waitingTagToAssociatedObj[structDict];
  }

  Object? saveAssociatedObjectForWaitingTag(Object associatedObj, PdfStructElem structElem) {
    _associatedObjToWaitingTag[associatedObj] = structElem;
    final prev = _waitingTagToAssociatedObj[structElem.getPdfObject()];
    _waitingTagToAssociatedObj[structElem.getPdfObject()] = associatedObj;
    return prev;
  }
}
