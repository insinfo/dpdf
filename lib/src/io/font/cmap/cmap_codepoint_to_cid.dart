import '../../util/int_hashtable.dart';
import 'abstract_cmap.dart';
import 'cmap_cid_to_codepoint.dart';
import 'cmap_object.dart';

class CMapCodepointToCid extends AbstractCMap {
  late final IntHashtable map;

  CMapCodepointToCid() {
    map = IntHashtable();
  }

  CMapCodepointToCid.fromReverseMap(CMapCidToCodepoint reverseMap) {
    map = reverseMap.getReversMap();
  }

  @override
  void addChar(String mark, CMapObject code) {
    if (code.isNumber()) {
      List<int> ser = AbstractCMap.decodeStringToByte(mark);
      int byteCode = 0;
      for (int b in ser) {
        byteCode <<= 8;
        byteCode += b & 0xFF;
      }
      map.put(byteCode, code.getValue() as int);
    }
  }

  int lookup(int codepoint) {
    return map.get(codepoint);
  }

  bool isEmpty() => map.isEmpty();
}
